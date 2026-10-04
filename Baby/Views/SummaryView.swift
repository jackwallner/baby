import Charts
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Upgrade becomes Reports in place when a purchase or restore unlocks Baby+.
struct ReportsTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: StoreService
    var isVisible = true
    var showsSnapshot = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isPro || showsSnapshot {
                    SummaryView()
                        .transition(.opacity)
                } else {
                    BabyPaywallView(displayCloseButton: false, paywallImpressionID: "baby_reports", closesOnPurchase: false, isVisible: isVisible)
                        .toolbar(.hidden, for: .navigationBar)
                        .transition(.opacity)
                }
            }
            .reservesNavigationCapsule()
        }
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: store.isPro)
    }
}

/// Baby+ reporting, read top to bottom: pick a range, see the day-by-day
/// averages, the chart behind each one, then hand the summary to the doctor.
/// Reached through the Reports tab once Baby+ is active. Before that the
/// paywall shows the same reports as previews (the example page in full when
/// nothing is logged, App Review 4.3).
struct SummaryView: View {
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var settings: BabySettings

    /// nil until the parent picks one: then a saved visit date means Custom,
    /// anything else the last two weeks.
    @State private var chosenRange: ReportRange?
    @State private var pdfData: Data?
    @State private var preview: UIImage?
    @State private var showFullPreview = false
    @State private var paywallFocus: PlusFeature?

    private var hasData: Bool { !events.events.isEmpty }
    private var isExample: Bool { !hasData }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                rangeSection
                if isExample {
                    Label("Example, not your baby's data. Log a few entries and this fills in.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                statsGrid
                ForEach(ReportMetric.shown(for: report.tracked), id: \.self) { metric in
                    chartCard(metric)
                }
                doctorCard
                Text(Guidance.disclaimer)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.margin)
            .padding(.vertical, AppTheme.spacing)
        }
        .background(AppTheme.paper)
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.large)
        .task(id: reportKey) { await rebuild() }
        .onChange(of: events.child?.objectID) { _, _ in chosenRange = nil }
        .sheet(isPresented: $showFullPreview) { fullPreview }
        .sheet(item: $paywallFocus) { focus in
            BabyPaywallView(paywallImpressionID: "baby_summary_\(focus.rawValue)", focus: focus)
        }
    }

    // MARK: - Range

    private var range: ReportRange {
        chosenRange ?? (events.child?.lastVisitAt == nil ? .twoWeeks : .custom)
    }

    private var rangeBinding: Binding<ReportRange> {
        Binding(get: { range }, set: { value in
            Haptics.selected()
            chosenRange = value
        })
    }

    /// Custom starts at the saved visit date, which is what the date row edits.
    private var customStart: Date { events.child?.lastVisitAt ?? events.defaultVisitStart }

    private var customBinding: Binding<Date> {
        Binding(get: { customStart }, set: { value in
            guard let child = events.child else { return }
            child.lastVisitAt = value
            _ = events.save()
        })
    }

    /// The range's first day, never before the first entry: days before the
    /// log began are not blank days, they are days nobody was logging.
    private var since: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = switch range {
        case .custom: customStart
        default: calendar.date(byAdding: .day, value: 1 - range.days, to: today) ?? today
        }
        guard let first = events.events.map(\.start).min() else { return start }
        return max(start, calendar.startOfDay(for: first))
    }

    private var reportKey: String {
        "\(events.revision)-\(DateHelpers.dayKey(for: since))-\(events.child?.id?.uuidString ?? "")-\(settings.tracked.hidden.count)"
    }

    private var report: SummaryReport { events.visitReport(since: isExample ? nil : since) }

    private func rebuild() async {
        let snapshot = report
        let example = isExample
        let data = await Task.detached(priority: .userInitiated) {
            PDFReport.render(snapshot, isExample: example)
        }.value
        let image = await Task.detached(priority: .userInitiated) {
            PDFReport.firstPageImage(data, width: 300)
        }.value
        guard !Task.isCancelled else { return }
        pdfData = data
        preview = image
    }

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            Picker("Range", selection: rangeBinding) {
                ForEach(ReportRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("reportRange")
            if range == .custom {
                LabeledContent("From") {
                    DatePicker("From", selection: customBinding, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                        .themedDatePicker()
                }
                .foregroundStyle(AppTheme.ink)
            }
            Text(rangeLine)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
        }
    }

    private var rangeLine: String {
        "\(rangeDates) · \(Format.count(report.dayCount, "day"))"
    }

    /// "Sep 28 to today".
    private var rangeDates: String {
        let start = report.start.formatted(.dateTime.month(.abbreviated).day())
        let end = Calendar.current.isDateInToday(report.end) ? "today" : report.end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) to \(end)"
    }

    // MARK: - At a glance

    /// One tile per button in use: the daily average, and the one number a
    /// doctor asks about next.
    private var statsGrid: some View {
        let tiles = statTiles
        return VStack(alignment: .leading, spacing: AppTheme.spacing) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { index in
                // Both tiles in a row share its height.
                HStack(alignment: .top, spacing: AppTheme.spacing) {
                    tiles[index]
                    if index + 1 < tiles.count {
                        tiles[index + 1]
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if report.completeDays.count < report.days.count {
                Text("Daily averages leave out today, which isn't over yet.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
        }
        .accessibilityIdentifier("summaryCard")
    }

    private var statTiles: [StatTile] {
        var tiles: [StatTile] = []
        if report.tracked.contains(.feed) {
            tiles.append(StatTile(kind: .feed, value: Self.decimal(report.averageFeedsPerDay), unit: "Feeds a day",
                                  detail: report.longestFeedGapSeconds > 0 ? "Longest gap \(Format.compactDuration(report.longestFeedGapSeconds))" : nil))
        }
        for kind in [EventKind.wet, .dirty] where report.tracked.contains(kind) {
            let average = kind == .wet ? report.averageWetPerDay : report.averageDirtyPerDay
            let total = kind == .wet ? report.totalWet : report.totalDirty
            tiles.append(StatTile(kind: kind, value: Self.decimal(average), unit: "\(kind.label) a day",
                                  detail: "\(total) in \(Format.count(report.dayCount, "day"))"))
        }
        if report.tracked.contains(.sleep) {
            tiles.append(StatTile(kind: .sleep, value: Format.compactDuration(report.averageSleepSeconds), unit: "Sleep a day",
                                  detail: report.longestSleepSeconds > 0 ? "Longest \(Format.compactDuration(report.longestSleepSeconds))" : nil))
        }
        return tiles
    }

    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    // MARK: - Charts

    private func chartCard(_ metric: ReportMetric) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(metric.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(ReportChart.takeaway(metric, report: report))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ReportChart(report: report, metric: metric)
        }
        .card(padding: AppTheme.compactCardPadding)
    }

    // MARK: - For the doctor

    private var doctorCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            SectionLabel(text: "For the doctor")
            Button {
                showFullPreview = true
            } label: {
                HStack(spacing: AppTheme.spacing) {
                    pageThumbnail
                    VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                        Text(isExample ? "Example summary" : "One-page summary")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text("Feeds, diapers, sleep and weights, \(rangeDates). Preview before sharing.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview the summary")
            shareButton
            Divider().overlay(AppTheme.separator)
            exportRow
        }
        .card(padding: AppTheme.compactCardPadding)
    }

    private var pageThumbnail: some View {
        Group {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .colorMultiply(AppTheme.codePaper)
            } else {
                Rectangle().fill(AppTheme.cardElevated)
            }
        }
        .frame(width: AppTheme.pageThumbnailWidth)
        .aspectRatio(612.0 / 792.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cellRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cellRadius, style: .continuous).strokeBorder(AppTheme.separator, lineWidth: AppTheme.hairlineWidth))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var shareButton: some View {
        if store.isPro, let pdfData, !isExample {
            Button { showFullPreview = true } label: {
                Label("Preview and share PDF", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("summary.previewAndSharePDF")
        } else if store.isPro {
            Button {} label: { Text("Log something to make your own") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
        } else {
            Button { paywallFocus = .pediatricianSummary } label: { Text("Get the PDF with Baby+") }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private var exportRow: some View {
        let label = HStack(spacing: AppTheme.spacing) {
            Image(systemName: "tablecells")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: AppTheme.pageThumbnailWidth)
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text("Spreadsheet (CSV)")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("Every entry, one row each, with times and notes.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: store.isPro ? "square.and.arrow.up" : "lock.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(hasData || !store.isPro ? AppTheme.accent : AppTheme.ink3)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if store.isPro, hasData {
            ShareLink(
                item: CSVFile(text: SummaryReport.csv(events: events.events, childName: report.childName), name: report.childName),
                preview: SharePreview("\(report.childName) log")
            ) { label }
            .buttonStyle(.plain)
            .accessibilityLabel("Export CSV")
        } else if store.isPro {
            label.opacity(0.5).accessibilityLabel("Log something to export")
        } else {
            Button { paywallFocus = .export } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Export with Baby+")
        }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showFullPreview = false }
                }
                if store.isPro, let pdfData, !isExample {
                    ToolbarItem(placement: .topBarTrailing) {
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

/// The report's range. Custom starts at the saved visit date.
enum ReportRange: CaseIterable, Hashable {
    case week, twoWeeks, month, custom

    var title: String {
        switch self {
        case .week: "7 days"
        case .twoWeeks: "14 days"
        case .month: "30 days"
        case .custom: "Custom"
        }
    }

    var days: Int {
        switch self {
        case .week: 7
        case .twoWeeks: 14
        case .month, .custom: 30
        }
    }
}

/// A number at a glance: a kind, its daily figure and one supporting line.
private struct StatTile: View {
    let kind: EventKind
    let value: String
    let unit: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
            HStack(spacing: AppTheme.hairSpacing) {
                KindDot(kind: kind, size: AppTheme.legendDotSize)
                Text(unit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: AppTheme.compactCardPadding)
        .accessibilityElement(children: .combine)
    }
}

/// Every page of the report, zoomable, the way it will print.
struct PDFPages: UIViewRepresentable {
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
        let tracked = TrackedKinds.current
        guard !events.isEmpty, let child else {
            var example = SampleReport.make()
            example.tracked = tracked
            return example
        }
        return SummaryReport.make(
            childName: child.displayName,
            birthDate: child.birthDate,
            events: events,
            from: since ?? defaultVisitStart,
            to: .now,
            tracked: tracked
        )
    }
}

/// What a report chart shows.
enum ReportMetric: CaseIterable, Hashable {
    case feeds, diapers, sleep

    var title: String {
        switch self {
        case .feeds: "Feeds a day"
        case .diapers: "Diapers a day"
        case .sleep: "Longest sleep stretch"
        }
    }

    static func shown(for tracked: TrackedKinds) -> [ReportMetric] {
        allCases.filter { metric in
            switch metric {
            case .feeds: tracked.contains(.feed)
            case .diapers: tracked.tracksDiapers
            case .sleep: tracked.contains(.sleep)
            }
        }
    }
}

/// One chart: a bar per day in the kind's colour, with a dashed line at the
/// daily average so a glance says whether a day was high or low.
struct ReportChart: View {
    let report: SummaryReport
    let metric: ReportMetric
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            if metric == .diapers, legend.count > 1 {
                HStack(spacing: AppTheme.spacing) {
                    ForEach(legend, id: \.0) { name, color in
                        HStack(spacing: AppTheme.hairSpacing) {
                            Circle().fill(color).frame(width: AppTheme.legendDotSize, height: AppTheme.legendDotSize)
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink2)
                        }
                    }
                }
            }
            chart
                .chartXScale(domain: report.start...(Calendar.current.date(byAdding: .day, value: 1, to: report.end) ?? report.end))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: labelStride)) { _ in
                        AxisValueLabel(format: labelFormat, centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(metric == .sleep ? "\(SummaryView.decimal(number))h" : SummaryView.decimal(number))
                            }
                        }
                    }
                }
                .frame(height: compact ? AppTheme.previewChartHeight : AppTheme.chartHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(Self.takeaway(metric, report: report))
    }

    private var chart: some View {
        Chart {
            switch metric {
            case .feeds:
                ForEach(report.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Feeds", day.feeds), width: .ratio(0.6))
                        .foregroundStyle(AppTheme.feed)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cellRadius, style: .continuous))
                }
                averageLine(report.averageFeedsPerDay)
            case .diapers:
                ForEach(report.days) { day in
                    ForEach(diaperKinds, id: \.self) { kind in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Count", kind == .wet ? day.wet : day.dirty),
                            width: .ratio(0.7)
                        )
                        .position(by: .value("Kind", kind.label))
                        .foregroundStyle(AppTheme.color(for: kind))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cellRadius, style: .continuous))
                    }
                }
            case .sleep:
                ForEach(report.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", day.longestSleepSeconds / 3600), width: .ratio(0.6))
                        .foregroundStyle(AppTheme.sleep)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cellRadius, style: .continuous))
                }
            }
        }
    }

    private func averageLine(_ value: Double) -> some ChartContent {
        RuleMark(y: .value("Average", value))
            .foregroundStyle(AppTheme.ink3)
            .lineStyle(StrokeStyle(lineWidth: AppTheme.hairlineWidth, dash: [AppTheme.hairSpacing, AppTheme.hairSpacing]))
    }

    private var diaperKinds: [EventKind] {
        [EventKind.wet, .dirty].filter { report.tracked.contains($0) }
    }

    private var legend: [(String, Color)] {
        diaperKinds.map { ($0.label, AppTheme.color(for: $0)) }
    }

    /// A label under every bar for a week; fewer, by date, beyond that.
    private var labelStride: Int {
        report.dayCount <= 7 ? 1 : Int((Double(report.dayCount) / (compact ? 3 : 5)).rounded(.up))
    }

    private var labelFormat: Date.FormatStyle {
        report.dayCount <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day()
    }

    /// The chart in one sentence, shown above it and read by VoiceOver.
    static func takeaway(_ metric: ReportMetric, report: SummaryReport) -> String {
        guard let latest = report.days.last else { return "Nothing logged in this range yet." }
        let latestName = Calendar.current.isDateInToday(latest.date) ? "today" : "on \(latest.date.formatted(.dateTime.month(.abbreviated).day()))"
        switch metric {
        case .feeds:
            return "About \(SummaryView.decimal(report.averageFeedsPerDay)) a day, \(latest.feeds) \(latestName)."
        case .diapers:
            let parts = [(EventKind.wet, report.averageWetPerDay), (.dirty, report.averageDirtyPerDay)]
                .filter { report.tracked.contains($0.0) }
                .map { "\(SummaryView.decimal($0.1)) \($0.0.label.lowercased())" }
            return "About \(parts.joined(separator: " and ")) a day."
        case .sleep:
            guard report.longestSleepSeconds > 0 else { return "No sleep logged in this range." }
            return "Longest \(Format.compactDuration(report.longestSleepSeconds)) in this range, \(Format.compactDuration(latest.longestSleepSeconds)) \(latestName)."
        }
    }
}

/// Every chart this family uses, stacked. The paywall's preview card shows
/// just the first, small.
struct ReportCharts: View {
    let report: SummaryReport
    var compact = false
    /// Just the first chart, for a preview card.
    var firstOnly = false

    var body: some View {
        let metrics = ReportMetric.shown(for: report.tracked)
        VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
            ForEach(firstOnly ? Array(metrics.prefix(1)) : metrics, id: \.self) { metric in
                VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                    Text(metric.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    ReportChart(report: report, metric: metric, compact: compact)
                }
            }
        }
    }
}
