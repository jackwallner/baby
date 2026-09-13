import SwiftUI

/// The long-press sheet, and the row editor in History. Time first, because
/// "it was actually twenty minutes ago" is the whole reason it exists.
struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var events: EventStore

    let request: EditorRequest

    @State private var kind: EventKind
    @State private var startedAt: Date
    @State private var side: FeedSide
    @State private var durationMinutes: Int
    @State private var amount: Double
    @State private var stool: StoolColor?
    @State private var note: String
    @State private var isTimed: Bool
    @State private var saveError: String?

    init(request: EditorRequest) {
        self.request = request
        let existing = request.existing
        _kind = State(initialValue: existing?.eventKind ?? request.kind)
        _startedAt = State(initialValue: existing?.startedAt ?? .now)
        _side = State(initialValue: existing?.feedSide ?? request.side ?? .left)
        let seconds = existing?.duration ?? 0
        _durationMinutes = State(initialValue: Int((seconds / 60).rounded()))
        _amount = State(initialValue: existing?.amount ?? 0)
        _stool = State(initialValue: existing?.stool)
        _note = State(initialValue: existing?.note ?? "")
        _isTimed = State(initialValue: existing?.isRunning ?? false)
    }

    private var isNew: Bool { request.existing == nil }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        DatePicker("Time", selection: $startedAt, in: ...Date.now.addingTimeInterval(60))
                    }
                    if kind == .feed {
                        Section("Feed") {
                            Picker("Side", selection: $side) {
                                ForEach(FeedSide.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if side == .bottle {
                                Stepper("Amount: \(Int(amount)) ml", value: $amount, in: 0...400, step: 10)
                            }
                            if isNew {
                                Toggle("Start a timer", isOn: $isTimed)
                            }
                            if !isTimed {
                                Stepper("Length: \(durationMinutes) min", value: $durationMinutes, in: 0...180, step: 1)
                            }
                        }
                    }
                    if kind == .dirty {
                        Section("Color") {
                            Picker("Color", selection: $stool) {
                                Text("Not noted").tag(StoolColor?.none)
                                ForEach(StoolColor.allCases, id: \.self) { Text($0.label).tag(StoolColor?.some($0)) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    if kind == .sleep, !isTimed {
                        Section("Sleep") {
                            Stepper("Length: \(Format.compactDuration(Double(durationMinutes) * 60))", value: $durationMinutes, in: 0...1440, step: 5)
                        }
                    }
                    if kind == .weight {
                        Section("Weight") {
                            Stepper("\(Format.grams(amount))", value: $amount, in: 500...15000, step: 10)
                        }
                    }
                    Section("Note") {
                        TextField("Optional", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                    }
                    if !isNew {
                        Section {
                            Button("Delete", role: .destructive) {
                                guard let existing = request.existing else { return }
                                if events.delete(existing) {
                                    dismiss()
                                } else {
                                    saveError = "Your log was not deleted. Please try again."
                                }
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
                .listRowBackground(AppTheme.card)
            }
            .foregroundStyle(AppTheme.ink)
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .tint(AppTheme.accent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Log" : "Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert(
            "Couldn't save changes",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Your changes were not saved. Please try again.")
        }
    }

    private var title: String {
        switch kind {
        case .feed: isNew ? "Log a feed" : "Feed"
        case .wet: isNew ? "Log a wet diaper" : "Wet diaper"
        case .dirty: isNew ? "Log a dirty diaper" : "Dirty diaper"
        case .sleep: isNew ? "Log sleep" : "Sleep"
        case .weight: isNew ? "Log a weight" : "Weight"
        }
    }

    private func save() {
        if let existing = request.existing {
            applyEdits(to: existing)
            guard events.save() else {
                saveError = "Your changes were not saved. Please try again."
                return
            }
            Haptics.logged()
            dismiss()
            return
        }

        let configure: (LogEvent) -> Void = { [self] event in
            applyEdits(to: event)
        }
        let event = if isTimed, kind.canRun {
            events.startTimed(kind, side: kind == .feed ? side : nil, at: startedAt, configure: configure)
        } else {
            events.log(kind, side: kind == .feed ? side : nil, at: startedAt, configure: configure)
        }
        guard event != nil else {
            saveError = "Your log was not saved. Please try again."
            return
        }
        Haptics.logged()
        dismiss()
    }

    private func applyEdits(to event: LogEvent) {
        event.startedAt = startedAt
        if kind == .feed { event.feedSide = side }
        if kind == .feed || kind == .weight { event.amount = amount }
        if kind == .dirty { event.stool = stool }
        if kind.canRun {
            event.endedAt = isTimed ? nil : startedAt.addingTimeInterval(Double(durationMinutes) * 60)
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        event.note = trimmed.isEmpty ? nil : trimmed
        event.updatedAt = .now
    }
}
