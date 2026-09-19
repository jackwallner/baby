import Charts
import PDFKit
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
                visitCard
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

    private var defaultSince: Date { events.defaultVisitStart }

    private var reportKey: String {
        "\(events.revision)-\(DateHelpers.dayKey(for: since))-\(events.child?.id?.uuidString ?? "")"
    }

    private var report: SummaryReport { events.visitReport(since: since) }

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

    /// The whole job of this page in one card: pick where the report starts,
    /// then hand it over. Everything below it is the preview and the extras.
    private var visitCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            SectionLabel(text: "For the next visit")
            LabeledContent("From") {
                DatePicker("From", selection: sinceBinding, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden()
                    .themedDatePicker()
            }
            .foregroundStyle(AppTheme.ink)
            Text(rangeLine)
                .font(.footnote)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            shareButton
            if hasData, Calendar.current.startOfDay(for: since) < Calendar.current.startOfDay(for: .now) {
                Button("Visit done? Start the next summary from today") {
                    sinceBinding.wrappedValue = Calendar.current.startOfDay(for: .now)
                    Haptics.selected()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minHeight: 44)
            }
        }
        .card()
        .accessibilityIdentifier("summaryCard")
    }

    private var rangeLine: String {
        if isExample {
            return "Log a few feeds and diapers and the page fills in with your own. Until then the preview is an example."
        }
        let days = report.dayCount
        return "\(since.formatted(.dateTime.month(.abbreviated).day())) to today, \(Format.count(days, "day")). One page to AirDrop, print or send to the office."
    }

    @ViewBuilder
    private var shareButton: some View {
        if store.isPro, let pdfData, !isExample {
            ShareLink(item: PDFFile(data: pdfData, name: report.childName, date: .now), preview: SharePreview("\(report.childName) summary")) {
                Label("Share PDF", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        } else if store.isPro {
            Button {} label: {
                Text("Log a feed to make your own").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(true)
        } else {
            Button {
                paywallFocus = .pediatricianSummary
            } label: {
                Text("Get the PDF with Baby+").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            HStack {
                SectionLabel(text: isExample ? "Example page" : "Preview")
                Spacer()
                Text(isExample ? "Made-up numbers" : "Tap to see every page")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.ink2)
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
        }
        .card()
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
            chart(title: "Diapers a day", legend: [(EventKind.wet.label, AppTheme.wet), (EventKind.dirty.label, AppTheme.dirty)], summary: "\(trendSummary(\.wet, unit: "wet")). \(trendSummary(\.dirty, unit: "dirty"))") {
                ForEach(report.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Wet", day.wet))
                        .foregroundStyle(AppTheme.wet)
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Dirty", day.dirty))
                        .foregroundStyle(AppTheme.dirty)
                }
            }
            chart(title: "Longest sleep stretch, hours", summary: sleepSummary) {
                // A day with no sleep logged is a gap in the line, not a zero.
                ForEach(report.days.filter { $0.longestSleepSeconds >= 60 }) { day in
                    // Midday, so each point sits over its day like the bars do.
                    LineMark(
                        x: .value("Day", day.date.addingTimeInterval(12 * 3600)),
                        y: .value("Hours", day.longestSleepSeconds / 3600)
                    )
                    .foregroundStyle(AppTheme.sleep)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Day", day.date.addingTimeInterval(12 * 3600)),
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

    private func chart<Content: ChartContent>(
        title: String,
        legend: [(String, Color)] = [],
        summary: String,
        @ChartContentBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            HStack(spacing: AppTheme.spacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                ForEach(legend, id: \.0) { name, color in
                    HStack(spacing: AppTheme.hairSpacing) {
                        Circle().fill(color).frame(width: AppTheme.dotSize * 2, height: AppTheme.dotSize * 2)
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink2)
                    }
                }
            }
            Chart(content: content)
                .chartXScale(domain: report.start...(Calendar.current.date(byAdding: .day, value: 1, to: report.end) ?? report.end))
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
            Group {
                if let pdfData {
                    PDFPages(data: pdfData)
                } else {
                    ProgressView()
                }
            }
            .background(AppTheme.paper)
            .navigationTitle(isExample ? "Example summary" : "Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFullPreview = false }
                }
                if store.isPro, let pdfData, !isExample {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: PDFFile(data: pdfData, name: report.childName, date: .now), preview: SharePreview("\(report.childName) summary")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share PDF")
                    }
                }
            }
        }
    }
}

/// Every page of the report, zoomable, the way it will print.
private struct PDFPages: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

/// Share wrappers, so the sheet hands over a real file with a real name
/// rather than a blob called "Item".
private struct PDFFile: Transferable {
    let data: Data
    let name: String
    let date: Date

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { file in file.data }
            .suggestedFileName { "\($0.name) summary \($0.date.formatted(.iso8601.year().month().day())).pdf" }
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

extension EventStore {
    /// Where the next summary starts: the day of the last visit, else birth
    /// for a baby under two weeks, else two weeks ago.
    var defaultVisitStart: Date {
        if let stored = child?.lastVisitAt { return stored }
        if let birth = child?.birthDate, birth > Date.now.addingTimeInterval(-14 * 86_400) { return birth }
        return Calendar.current.date(byAdding: .day, value: -13, to: .now) ?? .now
    }

    /// The report the summary page and the paywall both show. With nothing
    /// logged it is the labelled example.
    func visitReport(since: Date? = nil) -> SummaryReport {
        guard !events.isEmpty, let child else { return SampleReport.make() }
        return SummaryReport.make(
            childName: child.displayName,
            birthDate: child.birthDate,
            events: events,
            from: since ?? defaultVisitStart,
            to: .now
        )
    }
}
