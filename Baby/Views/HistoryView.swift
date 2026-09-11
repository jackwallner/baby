import SwiftUI

/// Every entry, newest first, grouped by day with the day's totals in the
/// header. Tap a row to edit it, swipe to delete. Never locked.
struct HistoryView: View {
    @EnvironmentObject private var events: EventStore
    @State private var editor: EditorRequest?

    var body: some View {
        Group {
            if events.events.isEmpty {
                emptyState
            } else {
                list
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

    private var list: some View {
        List {
            ForEach(events.eventsByDay, id: \.day) { group in
                Section {
                    ForEach(group.events, id: \.objectID) { event in
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
                } header: {
                    dayHeader(group.day, events: group.events)
                }
                .listRowBackground(AppTheme.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func dayHeader(_ day: Date, events dayEvents: [LogEvent]) -> some View {
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
        HStack(spacing: AppTheme.spacing) {
            KindDot(kind: event.eventKind)
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
                        .lineLimit(1)
                }
            }
            Spacer(minLength: AppTheme.tightSpacing)
            Text(Format.time(event.start))
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
