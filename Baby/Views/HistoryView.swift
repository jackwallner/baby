import SwiftUI

/// Every entry, as a list grouped by day or as a month calendar. Each day
/// carries its totals. Tap a row to edit it, swipe to delete. Never locked.
struct HistoryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var events: EventStore
    @AppStorage("historyLayout") private var layout = HistoryLayout.list
    @State private var editor: EditorRequest?
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    enum HistoryLayout: String, CaseIterable {
        case list
        case calendar

        var label: String {
            switch self {
            case .list: "List"
            case .calendar: "Calendar"
            }
        }
    }

    var body: some View {
        Group {
            if events.events.isEmpty {
                emptyState
            } else {
                switch layout {
                case .list: list
                case .calendar: calendar
                }
            }
        }
        .background(AppTheme.paper)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Feed") { editor = EditorRequest(kind: .feed) }
                    Button("Wet diaper") { editor = EditorRequest(kind: .wet) }
                    Button("Dirty diaper") { editor = EditorRequest(kind: .dirty) }
                    Button("Sleep") { editor = EditorRequest(kind: .sleep) }
                    Button("Weight") { editor = EditorRequest(kind: .weight) }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add an entry")
            }
        }
        .sheet(item: $editor) { request in
            EventEditorView(request: request)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.spacing) {
            Image(systemName: "list.bullet")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.ink3)
            Text("Nothing logged yet")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("Every tap on Now shows up here, with the day's totals.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: $layout) {
            ForEach(HistoryLayout.allCases, id: \.self) { layout in
                Text(layout.label).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("history.layout")
    }

    private var list: some View {
        List {
            Section { layoutPicker }
            ForEach(events.eventsByDay, id: \.day) { group in
                Section {
                    ForEach(group.events, id: \.objectID) { event in
                        eventRow(event)
                    }
                } header: {
                    dayHeader(group.day)
                }
                .themedRow()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var calendar: some View {
        let dayEvents = events.events.filter { Calendar.current.isDate($0.start, inSameDayAs: selectedDay) }
        return List {
            Section { layoutPicker }
            Section {
                MonthGrid(month: $month, selectedDay: $selectedDay, kindsByDay: kindsByDay, firstMonth: firstMonth)
            }
            .themedRow()
            Section {
                if dayEvents.isEmpty {
                    Text("Nothing logged this day")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink2)
                        .frame(minHeight: 44)
                } else {
                    ForEach(dayEvents, id: \.objectID) { event in
                        eventRow(event)
                    }
                }
            } header: {
                dayHeader(selectedDay)
            }
            .themedRow()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// Which kinds were logged on each day, for the calendar's dots.
    private var kindsByDay: [Date: Set<EventKind>] {
        var kinds: [Date: Set<EventKind>] = [:]
        for event in events.events {
            kinds[Calendar.current.startOfDay(for: event.start), default: []].insert(event.eventKind)
        }
        return kinds
    }

    private var firstMonth: Date {
        let earliest = (events.events.map(\.start) + [events.child?.birthDate].compactMap { $0 }).min() ?? .now
        return Calendar.current.startOfMonth(for: earliest)
    }

    private func eventRow(_ event: LogEvent) -> some View {
        Button {
            editor = EditorRequest(kind: event.eventKind, side: event.feedSide, existing: event)
        } label: {
            row(event)
        }
        .foregroundStyle(AppTheme.ink)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { events.delete(event) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        let tally = events.tally(on: day)
        var parts = ["\(tally.wet) wet", "\(tally.dirty) dirty", Format.count(tally.feeds, "feed")]
        if tally.sleepSeconds >= 60 { parts.append("\(Format.compactDuration(tally.sleepSeconds)) sleep") }
        return VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
            Text(Format.dayTitle(day))
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(AppTheme.ink2)
                .monospacedDigit()
        }
        .textCase(nil)
    }

    private func row(_ event: LogEvent) -> some View {
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.tightSpacing)) : AnyLayout(HStackLayout(spacing: AppTheme.spacing))) {
            KindIcon(kind: event.eventKind)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.eventKind.label)
                    .font(.body.weight(.medium))
                if let detail = event.detailText {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink2)
                }
                if let note = event.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: AppTheme.tightSpacing) }
            Text(Format.time(event.start))
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// One month of days, with a dot in the kind colour for each kind logged.
private struct MonthGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var month: Date
    @Binding var selectedDay: Date
    let kindsByDay: [Date: Set<EventKind>]
    let firstMonth: Date

    private let calendar = Calendar.current
    private static let dotKinds: [EventKind] = [.feed, .wet, .dirty, .sleep]

    var body: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            header
            // Plain stacks, not a lazy grid: a lazy grid inside a List cell
            // loops the collection view's self-sizing and crashes.
            VStack(spacing: AppTheme.hairSpacing) {
                week(weekdaySymbols.map { symbol in
                    AnyView(Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.ink3))
                })
                .accessibilityHidden(true)
                ForEach(weeks.indices, id: \.self) { index in
                    week(weeks[index].map { day in
                        day.map { AnyView(dayCell($0)) } ?? AnyView(Color.clear.frame(height: 1))
                    })
                }
            }
        }
        .padding(.vertical, AppTheme.tightSpacing)
        .gesture(DragGesture(minimumDistance: AppTheme.looseSpacing).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            if value.translation.width < 0, canGoForward { step(1) }
            if value.translation.width > 0, canGoBack { step(-1) }
        })
    }

    private var header: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!canGoBack)
                .accessibilityLabel("Previous month")
            Spacer(minLength: 0)
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Spacer(minLength: 0)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!canGoForward)
                .accessibilityLabel("Next month")
        }
        .buttonStyle(.borderless)
        .font(.body.weight(.semibold))
        .tint(AppTheme.accent)
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > .now
        let kinds = Self.dotKinds.filter { (kindsByDay[day] ?? []).contains($0) }
        return Button {
            Haptics.selected()
            selectedDay = day
        } label: {
            VStack(spacing: AppTheme.hairSpacing) {
                Text(day.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isToday || isSelected ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AppTheme.buttonInk : (isFuture ? AppTheme.ink3 : AppTheme.ink))
                    .frame(width: AppTheme.iconSize, height: AppTheme.iconSize)
                    .background {
                        if isSelected {
                            Circle().fill(AppTheme.actionFill)
                        } else if isToday {
                            Circle().strokeBorder(AppTheme.accent, lineWidth: AppTheme.hairlineWidth)
                        }
                    }
                HStack(spacing: AppTheme.dotSize / 2) {
                    ForEach(kinds, id: \.self) { kind in
                        Circle()
                            .fill(AppTheme.color(for: kind))
                            .frame(width: AppTheme.dotSize, height: AppTheme.dotSize)
                    }
                }
                .frame(height: AppTheme.dotSize)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isFuture)
        .accessibilityLabel(accessibilityLabel(day, kinds: kinds))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(_ day: Date, kinds: [EventKind]) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return kinds.isEmpty ? date : "\(date), \(kinds.map(\.label).joined(separator: ", "))"
    }

    private func week(_ cells: [AnyView]) -> some View {
        HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { index in
                cells[index].frame(maxWidth: .infinity)
            }
        }
    }

    /// The month in rows of seven, padded with blanks at both ends.
    private var weeks: [[Date?]] {
        var cells = days
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Leading blanks up to the month's first weekday, then each day.
    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: offset) + dates
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var canGoBack: Bool { month > firstMonth }
    private var canGoForward: Bool { month < calendar.startOfMonth(for: .now) }

    private func step(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        withAnimation(reduceMotion ? nil : AppTheme.feedbackAnimation) { month = next }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
