import Charts
import SwiftUI

/// What one day's line says, shared by History's day headers, the Today and
/// Yesterday tiles and the day chart: "9 feeds · 6 pee · 3 poop · 11h sleep".
enum DayLine {
    static func parts(_ tally: DayTally, tracked: TrackedKinds) -> [String] {
        var parts: [String] = []
        if tracked.contains(.feed) { parts.append(Format.count(tally.feeds, "feed")) }
        if tracked.contains(.wet) { parts.append("\(tally.wet) \(EventKind.wet.label.lowercased())") }
        if tracked.contains(.dirty) { parts.append("\(tally.dirty) \(EventKind.dirty.label.lowercased())") }
        if tracked.contains(.sleep), tally.sleepSeconds >= 60 { parts.append("\(Format.compactDuration(tally.sleepSeconds)) sleep") }
        return parts
    }

    static func text(_ tally: DayTally, tracked: TrackedKinds) -> String {
        parts(tally, tracked: tracked).joined(separator: " · ")
    }
}

/// The day chart's bars: one per day, the first tracked of feeds, diapers or
/// sleep. Pure, so tests read it directly.
struct DayChartModel: Equatable {
    enum Metric: Equatable {
        case feeds
        case diapers
        case sleep

        init(tracked: TrackedKinds) {
            if tracked.contains(.feed) {
                self = .feeds
            } else if tracked.tracksDiapers {
                self = .diapers
            } else {
                self = .sleep
            }
        }

        var title: String {
            switch self {
            case .feeds: "Feeds per day"
            case .diapers: "Diapers per day"
            case .sleep: "Sleep per day"
            }
        }

        var kind: EventKind {
            switch self {
            case .feeds: .feed
            case .diapers: .wet
            case .sleep: .sleep
            }
        }

        func value(_ tally: DayTally, tracked: TrackedKinds) -> Double {
            switch self {
            case .feeds: Double(tally.feeds)
            case .diapers: Double((tracked.contains(.wet) ? tally.wet : 0) + (tracked.contains(.dirty) ? tally.dirty : 0))
            case .sleep: tally.sleepSeconds / 3600
            }
        }
    }

    struct Bar: Identifiable, Equatable {
        var day: Date
        var value: Double
        var tally: DayTally
        var isToday: Bool
        var id: Date { day }
    }

    static let dayCount = 14

    var metric: Metric
    var bars: [Bar]

    /// The last two weeks through today, never before the first entry.
    static func days(through today: Date, firstEntry: Date?, calendar: Calendar = .current) -> [Date] {
        let end = calendar.startOfDay(for: today)
        let earliest = calendar.date(byAdding: .day, value: -(dayCount - 1), to: end) ?? end
        let first = firstEntry.map { calendar.startOfDay(for: $0) } ?? end
        let start = min(max(earliest, first), end)
        var days: [Date] = []
        var day = start
        while day <= end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    static func make(events: [LogEvent], tracked: TrackedKinds, now: Date = .now, calendar: Calendar = .current) -> DayChartModel {
        make(firstEntry: events.map(\.start).min(), tracked: tracked, now: now, calendar: calendar) {
            DayTally.make(events: events, on: $0, now: now, calendar: calendar)
        }
    }

    /// From day totals the caller already has, so a render does not walk the
    /// whole log once per bar.
    static func make(
        firstEntry: Date?,
        tracked: TrackedKinds,
        now: Date = .now,
        calendar: Calendar = .current,
        tally: (Date) -> DayTally
    ) -> DayChartModel {
        let metric = Metric(tracked: tracked)
        let days = days(through: now, firstEntry: firstEntry, calendar: calendar)
        let bars = days.map { day in
            let tally = tally(day)
            return Bar(day: day, value: metric.value(tally, tracked: tracked), tally: tally, isToday: calendar.isDate(day, inSameDayAs: now))
        }
        return DayChartModel(metric: metric, bars: bars)
    }
}

/// Today and Yesterday side by side, free: one tap opens that day's entries.
struct DayJumpTiles: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var settings: BabySettings
    let onJump: (Date) -> Void

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: AppTheme.tightSpacing))
            : AnyLayout(HStackLayout(spacing: AppTheme.tightSpacing))) {
            tile(today, id: "today")
            tile(yesterday, id: "yesterday")
        }
    }

    private func tile(_ day: Date, id: String) -> some View {
        let tally = events.tally(on: day)
        let parts = DayLine.parts(tally, tracked: settings.tracked)
        let hasEntries = events.hasEntries(on: day)
        return Button {
            Haptics.selected()
            onJump(day)
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(Format.dayTitle(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink2)
                Text(hasEntries ? (parts.first ?? "") : "Nothing logged")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(hasEntries ? AppTheme.ink : AppTheme.ink3)
                    .monospacedDigit()
                // "3h 45m sleep" wraps as one piece, never between its numbers.
                Text(parts.dropFirst().map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
                    .monospacedDigit()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .padding(AppTheme.spacing)
            .background(AppTheme.cardElevated, in: AppTheme.buttonShape)
            .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
            .contentShape(AppTheme.buttonShape)
        }
        .buttonStyle(.borderless)
        .disabled(!hasEntries)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Format.dayTitle(day))
        .accessibilityValue(hasEntries ? parts.joined(separator: ", ") : "Nothing logged")
        .accessibilityHint(hasEntries ? "Shows that day's entries" : "")
        .accessibilityIdentifier("history.jump.\(id)")
    }
}

/// Baby+: drag across the bars and the header reads out the day under your
/// finger, the way Total Calories' charts do; let go and History opens that
/// day. Without Baby+ the baby's own bars sit blurred under one lock.
struct DayScrubChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var settings: BabySettings
    @EnvironmentObject private var store: StoreService
    let onJump: (Date) -> Void

    @State private var scrubDate: Date?
    @State private var scrubbedDay: Date?
    @State private var showsPaywall = false

    var body: some View {
        // Newest first, so the first entry is the last one.
        let model = DayChartModel.make(firstEntry: events.events.last?.start, tracked: settings.tracked) { events.tally(on: $0) }
        let isUnlocked = store.isPro || ScreenshotConfig.isEnabled
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            header(model, isUnlocked: isUnlocked)
            if isUnlocked {
                chart(model)
                    .chartXSelection(value: $scrubDate)
            } else {
                Button { showsPaywall = true } label: {
                    chart(model)
                        .blur(radius: AppTheme.previewBlur)
                        .allowsHitTesting(false)
                        .overlay { lockBadge }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(model.metric.title), Baby+")
                .accessibilityHint("Shows Baby+")
                .accessibilityIdentifier("history.dayChart.locked")
            }
        }
        .card(padding: AppTheme.spacing)
        .onChange(of: scrubDate) { _, date in scrubChanged(date) }
        .sheet(isPresented: $showsPaywall) {
            BabyPaywallView(paywallImpressionID: "baby_history_chart", focus: .trends)
        }
    }

    @ViewBuilder
    private func header(_ model: DayChartModel, isUnlocked: Bool) -> some View {
        let selected = scrubbedDay.flatMap { day in model.bars.first { $0.day == day } }
        VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
            if let selected {
                Text(Format.dayTitle(selected.day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink2)
                Text(DayLine.text(selected.tally, tracked: settings.tracked))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(model.metric.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(isUnlocked ? "Drag across a day to see it" : "Drag through any day with Baby+")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.dayChart.header")
    }

    private func chart(_ model: DayChartModel) -> some View {
        let color = AppTheme.color(for: model.metric.kind)
        let last = model.bars.last?.day ?? .now
        let domainEnd = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last
        return Chart(model.bars) { bar in
            BarMark(x: .value("Day", bar.day, unit: .day), y: .value(model.metric.title, bar.value), width: .ratio(0.6))
                .foregroundStyle(color)
                .opacity(opacity(for: bar))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cellRadius, style: .continuous))
                .accessibilityLabel(Format.dayTitle(bar.day))
                .accessibilityValue(DayLine.text(bar.tally, tracked: settings.tracked))
        }
        .chartXScale(domain: (model.bars.first?.day ?? last)...domainEnd)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: model.bars.count > 7 ? 2 : 1)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(model.metric == .sleep ? "\(Int(number))h" : "\(Int(number))")
                    }
                }
            }
        }
        .frame(height: AppTheme.chartHeight)
        .accessibilityIdentifier("history.dayChart")
    }

    /// Today is still filling in, so it is drawn lighter; while a finger is
    /// down, every other day steps back.
    private func opacity(for bar: DayChartModel.Bar) -> Double {
        let base = bar.isToday ? AppTheme.partialBarOpacity : 1
        guard let scrubbedDay else { return base }
        return bar.day == scrubbedDay ? 1 : base * 0.3
    }

    private var lockBadge: some View {
        HStack(spacing: AppTheme.hairSpacing) {
            Image(systemName: "lock.fill")
            Text("Baby+")
        }
        .font(.caption.weight(.semibold))
        .fixedSize()
        .foregroundStyle(AppTheme.ink)
        .padding(.horizontal, AppTheme.tightSpacing)
        .padding(.vertical, AppTheme.hairSpacing)
        .background(AppTheme.cardElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.edge, lineWidth: AppTheme.hairlineWidth))
    }

    private func scrubChanged(_ date: Date?) {
        guard let date else {
            if let day = scrubbedDay { onJump(day) }
            withAnimation(reduceMotion ? nil : AppTheme.feedbackAnimation) { scrubbedDay = nil }
            return
        }
        let day = Calendar.current.startOfDay(for: date)
        guard day != scrubbedDay, day <= Calendar.current.startOfDay(for: .now) else { return }
        Haptics.selected()
        scrubbedDay = day
    }
}
