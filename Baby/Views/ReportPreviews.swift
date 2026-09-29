import SwiftUI

/// The paywall's pitch is the reports themselves: the summary page, a trend
/// chart and the export, drawn from this baby's log. Before anything is
/// logged each card is the labelled example, readable in full (App Review
/// 4.3). Once the log is the baby's own, the part Baby+ unlocks is blurred
/// behind one lock, the same way on every card.
struct ReportPreviews: View {
    @EnvironmentObject private var events: EventStore
    var focus: PlusFeature?

    @State private var page: UIImage?
    @State private var pageData: Data?
    @State private var showExample = false
    @State private var position: PlusFeature?

    private var isExample: Bool { events.events.isEmpty }

    var body: some View {
        let report = events.visitReport()
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: AppTheme.spacing) {
                card(.pediatricianSummary) { summaryPage }
                card(.trends) {
                    ReportCharts(report: trendsReport, compact: true, firstOnly: true)
                        .padding(AppTheme.spacing)
                        .blur(radius: isExample ? 0 : AppTheme.previewBlur)
                }
                card(.export) { exportRows(report) }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position)
        .contentMargins(.horizontal, AppTheme.margin, for: .scrollContent)
        .scrollIndicators(.hidden)
        .task(id: events.revision) { await renderPage(report) }
        .onAppear { position = focus }
        .sheet(isPresented: $showExample) { exampleSheet }
    }

    /// At least a week, so a three-day-old log draws bars, not a slab.
    private var trendsReport: SummaryReport {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return isExample ? events.visitReport() : events.visitReport(since: min(events.defaultVisitStart, weekAgo))
    }

    // MARK: - Card

    private func card<Content: View>(_ feature: PlusFeature, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            content()
                .frame(width: AppTheme.previewCardWidth, height: AppTheme.previewCardHeight, alignment: .top)
                .background(AppTheme.card)
                .clipShape(AppTheme.cardShape)
                .overlay(alignment: isExample ? .topTrailing : .center) { badge }
                .graphicBorder()
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(feature.pitchLine)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hairSpacing)
        }
        .frame(width: AppTheme.previewCardWidth)
        .id(feature)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title). \(feature.pitchLine)")
        .accessibilityValue(isExample ? "Example with made-up numbers" : "Preview of your baby's log, unlocks with Baby+")
        .accessibilityIdentifier("paywall.preview.\(feature.rawValue)")
    }

    /// "Example" in the corner, or the one lock over the blurred part.
    private var badge: some View {
        Label(isExample ? "Example" : "Baby+", systemImage: isExample ? "doc.text.magnifyingglass" : "lock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isExample ? AppTheme.ink2 : AppTheme.ink)
            .padding(.horizontal, AppTheme.tightSpacing)
            .padding(.vertical, AppTheme.hairSpacing)
            .background(AppTheme.cardElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
            .padding(AppTheme.tightSpacing)
            .accessibilityHidden(true)
    }

    // MARK: - Summary page

    /// The page's name and range stay sharp so it is recognisably theirs;
    /// the numbers under them are what Baby+ hands over.
    @ViewBuilder
    private var summaryPage: some View {
        if let page {
            let image = Image(uiImage: page).resizable().aspectRatio(contentMode: .fit).colorMultiply(AppTheme.codePaper)
            if isExample {
                Button { showExample = true } label: { image }
                    .pressableCard()
                    .accessibilityHint("Opens every page of the example")
            } else {
                ZStack(alignment: .top) {
                    image.blur(radius: AppTheme.previewBlur)
                    image.mask(LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.2), .init(color: .clear, location: 0.27)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func renderPage(_ report: SummaryReport) async {
        let example = isExample
        let data = await Task.detached(priority: .userInitiated) {
            PDFReport.render(report, isExample: example)
        }.value
        let image = await Task.detached(priority: .userInitiated) {
            PDFReport.firstPageImage(data, width: AppTheme.previewCardWidth * 1.5, crop: PDFReport.previewCrop)
        }.value
        guard !Task.isCancelled else { return }
        pageData = data
        page = image
    }

    private var exampleSheet: some View {
        NavigationStack {
            Group {
                if let pageData { PDFPages(data: pageData) } else { ProgressView() }
            }
            .background(AppTheme.paper)
            .navigationTitle("Example summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showExample = false }
                }
            }
        }
    }

    // MARK: - Export

    private func exportRows(_ report: SummaryReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(["time", "kind", "detail"], header: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows(report).enumerated()), id: \.offset) { _, cells in
                    Divider().overlay(AppTheme.separator)
                    row(cells, header: false)
                }
            }
            .blur(radius: isExample ? 0 : AppTheme.previewBlur)
        }
        .padding(AppTheme.spacing)
        .accessibilityHidden(true)
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: AppTheme.tightSpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.caption.monospaced().weight(header ? .semibold : .regular))
                    .foregroundStyle(header ? AppTheme.ink2 : AppTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, AppTheme.hairSpacing)
    }

    /// The newest entries as the spreadsheet will have them, or made-up ones.
    private func rows(_ report: SummaryReport) -> [[String]] {
        if isExample {
            let example: [(EventKind, String, String)] = [
                (.feed, "7:40 AM", "left"), (.wet, "7:10 AM", ""), (.dirty, "6:55 AM", "yellow"),
                (.sleep, "4:20 AM", "2h 10m"), (.feed, "3:50 AM", "bottle"),
            ]
            return example.filter { report.tracked.contains($0.0) }.map { [$0.1, $0.0.rawValue, $0.2] }
        }
        return events.events.prefix(5).map { event in
            [Format.time(event.start), event.eventKind.rawValue, event.detailText ?? ""]
        }
    }
}
