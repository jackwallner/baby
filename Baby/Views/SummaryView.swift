import Charts
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The reporting tab: the pediatrician summary, the trends behind it, and the
/// export. The page itself is always visible, with or without data and with or
/// without Baby+ (App Review 4.3); Baby+ is what hands you the file.
struct SummaryView: View {
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var store: StoreService

    /// nil until the child is known. Resolving it lazily rather than in
    /// `onAppear` keeps the first render from using today and then flickering
    /// to the real range.
    @State private var chosenSince: Date?
    @State private var pdfData: Data?
    @State private var preview: UIImage?
    @State private var showFullPreview = false
    @State private var paywallFocus: PlusFeature?
    @State private var csvURL: URL?

    private var hasData: Bool { !events.events.isEmpty }
    private var isExample: Bool { !hasData }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                sinceCard
                previewCard
                trendsCard
                exportCard
                Text(Guidance.disclaimer)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.margin)
            .padding(.vertical, AppTheme.spacing)
        }
        .background(AppTheme.paper)
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.large)
        .task(id: reportKey) { await rebuild() }
        .onChange(of: events.child?.objectID) { _, _ in chosenSince = nil }
        .sheet(isPresented: $showFullPreview) { fullPreview }
        .sheet(item: $paywallFocus) { focus in
            BabyPaywallView(paywallImpressionID: "baby_summary_\(focus.rawValue)", focus: focus)
        }
    }

    // MARK: - Report

    private var since: Date { chosenSince ?? defaultSince }

    private var sinceBinding: Binding<Date> {
        Binding(get: { since }, set: { value in
            guard let child = events.child else { return }
            child.lastVisitAt = value
            if events.save() {
                chosenSince = value
            }
        })
    }

    private var defaultSince: Date {
        if let stored = events.child?.lastVisitAt { return stored }
        if let birth = events.child?.birthDate, birth > Date.now.addingTimeInterval(-14 * 86_400) { return birth }
        return Calendar.current.date(byAdding: .day, value: -13, to: .now) ?? .now
    }

    private var reportKey: String {
        "\(events.revision)-\(DateHelpers.dayKey(for: since))-\(events.child?.id?.uuidString ?? "")"
    }

    private var report: SummaryReport {
        guard hasData, let child = events.child else { return SampleReport.make() }
        return SummaryReport.make(
            childName: child.displayName,
            birthDate: child.birthDate,
            events: events.events,
            from: since,
            to: .now
        )
    }

    private func rebuild() async {
        let snapshot = report
        let example = isExample
        let data = await Task.detached(priority: .userInitiated) {
            PDFReport.render(snapshot, isExample: example)
        }.value
        let image = await Task.detached(priority: .userInitiated) {
            PDFReport.firstPageImage(data, width: 900)
        }.value
        guard !Task.isCancelled else { return }
        pdfData = data
        preview = image
    }

    // MARK: - Cards

    private var sinceCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            SectionLabel(text: "Since the last visit")
            DatePicker("First day", selection: sinceBinding, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.compact)
            Button("Today was the visit") {
                sinceBinding.wrappedValue = Calendar.current.startOfDay(for: .now)
                Haptics.selected()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
            .frame(minHeight: 44)
            Text("Choose a start date. Bring a simple record of feeds, diapers and sleep to your next visit.")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            HStack {
                SectionLabel(text: isExample ? "Example summary" : "Your summary")
                Spacer()
                if isExample {
                    Text("Made-up numbers")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.ink2)
                }
            }
            Button {
                showFullPreview = true
            } label: {
                Group {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .colorMultiply(AppTheme.codePaper)
                    } else {
                        Rectangle()
                            .fill(AppTheme.cardElevated)
                            .aspectRatio(612.0 / 792.0, contentMode: .fit)
                            .overlay(ProgressView())
                    }
                }
                .clipShape(AppTheme.cardShape)
                .overlay(AppTheme.cardShape.stroke(AppTheme.ink3.opacity(0.25), lineWidth: 1))
                .accessibilityLabel("Preview of the pediatrician summary")
            }
            .pressableCard()

            Text(isExample
                 ? "This is what you hand over at the visit. Log a few feeds and diapers and it fills in with your own."
                 : "One page since \(since.formatted(.dateTime.month(.abbreviated).day())): feeds, wet and dirty counts, sleep, and weights.")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if store.isPro, let pdfData, !isExample {
                ShareLink(item: PDFFile(data: pdfData, name: report.childName), preview: SharePreview("\(report.childName) summary")) {
                    Text("Share PDF").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    paywallFocus = .pediatricianSummary
                } label: {
                    Text(isExample && store.isPro ? "Log a feed to make your own" : "Get the PDF with Baby+")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isExample && store.isPro)
            }
        }
        .card()
        .accessibilityIdentifier("summaryCard")
    }

    private var trendsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            SectionLabel(text: "Trends")
            ZStack {
                charts
                    .blur(radius: store.isPro ? 0 : 7)
                    .allowsHitTesting(store.isPro)
                    .accessibilityHidden(!store.isPro)
                if !store.isPro {
                    VStack(spacing: AppTheme.tightSpacing) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text("Your own weeks, in Baby+")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
            }
            if !store.isPro {
                Button("See Baby+") { paywallFocus = .trends }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
            }
        }
        .card()
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
            chart(title: "Feeds a day", summary: trendSummary(\.feeds, unit: "feeds")) {
                ForEach(report.days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Feeds", day.feeds)
                    )
                    .foregroundStyle(AppTheme.feed)
                }
            }
            chart(title: "Diapers a day", summary: "\(trendSummary(\.wet, unit: "wet")). \(trendSummary(\.dirty, unit: "dirty"))") {
                ForEach(report.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Wet", day.wet))
                        .foregroundStyle(AppTheme.wet)
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Dirty", day.dirty))
                        .foregroundStyle(AppTheme.dirty)
                }
            }
            chart(title: "Longest sleep stretch", summary: sleepSummary) {
                ForEach(report.days) { day in
                    LineMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Hours", day.longestSleepSeconds / 3600)
                    )
                    .foregroundStyle(AppTheme.sleep)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Hours", day.longestSleepSeconds / 3600)
                    )
                    .foregroundStyle(AppTheme.sleep)
                }
            }
        }
    }

    /// What a chart says, for VoiceOver: the daily average and the latest day.
    private func trendSummary(_ value: KeyPath<SummaryReport.Day, Int>, unit: String) -> String {
        guard let latest = report.days.last, !report.days.isEmpty else { return "No days yet" }
        let average = Double(report.days.map { $0[keyPath: value] }.reduce(0, +)) / Double(report.days.count)
        return "Average \(average.formatted(.number.precision(.fractionLength(0...1)))) \(unit) a day, \(latest[keyPath: value]) on the latest day"
    }

    private var sleepSummary: String {
        guard let latest = report.days.last, let longest = report.days.map(\.longestSleepSeconds).max() else { return "No days yet" }
        return "Longest \(Format.compactDuration(longest)) in this range, \(Format.compactDuration(latest.longestSleepSeconds)) on the latest day"
    }

    private func chart<Content: ChartContent>(title: String, summary: String, @ChartContentBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Chart(content: content)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, report.dayCount / 5))) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 120)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            SectionLabel(text: "Export")
            Text("Every entry as a spreadsheet: one row per feed, diaper, sleep and weight, with the time and any note.")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if store.isPro, hasData {
                ShareLink(
                    item: CSVFile(text: SummaryReport.csv(events: events.events, childName: report.childName), name: report.childName),
                    preview: SharePreview("\(report.childName) log")
                ) {
                    Text("Export CSV").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Export with Baby+") { paywallFocus = .export }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(store.isPro && !hasData)
            }
        }
        .card()
    }

    private var fullPreview: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(minWidth: 320)
                }
            }
            .background(AppTheme.paper)
            .navigationTitle(isExample ? "Example summary" : "Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFullPreview = false }
                }
            }
        }
    }
}

/// Share wrappers, so the sheet hands over a real file with a real name
/// rather than a blob called "Item".
private struct PDFFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { file in file.data }
            .suggestedFileName { "\($0.name) summary.pdf" }
    }
}

private struct CSVFile: Transferable {
    let text: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { "\($0.name) log.csv" }
    }
}
