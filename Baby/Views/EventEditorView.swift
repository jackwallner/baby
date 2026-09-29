import SwiftUI

/// The long-press sheet, and the row editor in History. Time first, because
/// "it was actually twenty minutes ago" is the whole reason it exists. The
/// time is an inline wheel, never a popover that could cover the bar.
///
/// An existing entry saves as it changes: there is no Save to find, and
/// closing the sheet any way keeps the edit. A new entry needs Log, so a
/// sheet opened by accident never adds a row.
struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var events: EventStore

    let request: EditorRequest

    @State private var kind: EventKind
    @State private var draft: Draft
    @State private var saveError: String?
    @State private var pendingSave: Task<Void, Never>?

    /// Everything the form edits, compared as one value so any change
    /// schedules one autosave.
    struct Draft: Equatable {
        var startedAt: Date
        var sides: [FeedSide]
        var durationMinutes: Int
        var amount: Double
        var stool: StoolColor?
        var note: String
        var isTimed: Bool
    }

    /// Long enough for a wheel to settle and a word to be typed.
    static let autosaveDelay: Duration = .milliseconds(600)

    init(request: EditorRequest) {
        self.request = request
        let existing = request.existing
        _kind = State(initialValue: existing?.eventKind ?? request.kind)
        let seconds = existing?.duration ?? 0
        _draft = State(initialValue: Draft(
            startedAt: existing?.startedAt ?? request.at ?? .now,
            sides: existing?.feedSides ?? [],
            durationMinutes: Int((seconds / 60).rounded()),
            amount: existing?.amount ?? 0,
            stool: existing?.stool,
            note: existing?.note ?? "",
            isTimed: existing?.isRunning ?? false
        ))
    }

    private var isNew: Bool { request.existing == nil }

    /// A new weigh-in starts at the last one, so the wheels are a nudge away
    /// from the scale's reading rather than a long spin from zero.
    private var startingWeight: Double {
        events.events
            .filter { $0.eventKind == .weight && $0.amount > 0 }
            .max { $0.start < $1.start }?
            .amount ?? 3400
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        DatePicker("Time", selection: $draft.startedAt, in: ...Date.now.addingTimeInterval(60))
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .themedDatePicker()
                            .accessibilityIdentifier("editor.time")
                    } header: {
                        Text(timeHeader)
                    }
                    if kind == .feed {
                        Section {
                            FeedSideChips(selection: $draft.sides)
                                .listRowInsets(EdgeInsets(top: AppTheme.spacing, leading: AppTheme.spacing, bottom: AppTheme.spacing, trailing: AppTheme.spacing))
                            if draft.sides.contains(.bottle) {
                                Stepper("Amount: \(Format.millilitres(draft.amount))", value: $draft.amount, in: 0...400,
                                        step: Format.usesImperial ? Format.millilitresPerOunce / 2 : 10)
                            }
                            if isNew {
                                Toggle("Start a timer", isOn: $draft.isTimed)
                            }
                            if !draft.isTimed {
                                Stepper("Length: \(draft.durationMinutes) min", value: $draft.durationMinutes, in: 0...180, step: 1)
                            }
                        } header: {
                            Text("Side (optional)")
                        }
                    }
                    if kind == .dirty {
                        Section("Color") {
                            Picker("Color", selection: $draft.stool) {
                                Text("Not noted").tag(StoolColor?.none)
                                ForEach(StoolColor.allCases, id: \.self) { Text($0.label).tag(StoolColor?.some($0)) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    if kind == .sleep, !draft.isTimed {
                        Section("Sleep") {
                            Stepper("Length: \(Format.compactDuration(Double(draft.durationMinutes) * 60))", value: $draft.durationMinutes, in: 0...1440, step: 5)
                        }
                    }
                    if kind == .weight {
                        Section("Weight") {
                            WeightPicker(grams: $draft.amount)
                        }
                    }
                    Section {
                        TextField("Optional", text: $draft.note, axis: .vertical)
                            .lineLimit(1...3)
                            .accessibilityIdentifier("editor.note")
                    } header: {
                        Text("Note")
                    } footer: {
                        if !isNew { Text("Changes save as you make them.") }
                    }
                    if !isNew {
                        Section {
                            Button("Delete", role: .destructive) {
                                guard let existing = request.existing else { return }
                                pendingSave?.cancel()
                                pendingSave = nil
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
                .themedRow()
            }
            .foregroundStyle(AppTheme.ink)
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .tint(AppTheme.accent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isNew {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Log") { logNew() }
                            .fontWeight(.semibold)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if saveNow() { dismiss() }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .onAppear {
            if isNew, kind == .weight, draft.amount <= 0 { draft.amount = startingWeight }
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onDisappear {
            // Swiped away mid-edit: keep what was changed.
            if pendingSave != nil { saveNow() }
        }
        .presentationDetents([.large])
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
        case .wet, .dirty: isNew ? "Log a \(kind.label.lowercased()) diaper" : "\(kind.label) diaper"
        case .sleep: isNew ? "Log sleep" : "Sleep"
        case .weight: isNew ? "Log a weight" : "Weight"
        }
    }

    /// "Time · 12m ago", so the wheel's answer reads back in plain words.
    private var timeHeader: String {
        let seconds = Date.now.timeIntervalSince(draft.startedAt)
        return seconds < 60 ? "Time · now" : "Time · \(Format.ago(draft.startedAt))"
    }

    // MARK: - Saving

    private func scheduleSave() {
        guard !isNew else { return }
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    /// Writes the draft to the existing entry. True when there is nothing
    /// left unsaved.
    @discardableResult
    private func saveNow() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard let existing = request.existing, !existing.isDeleted, existing.managedObjectContext != nil else { return true }
        applyEdits(to: existing)
        guard existing.hasChanges else { return true }
        guard events.save() else {
            saveError = "Your changes were not saved. Please try again."
            return false
        }
        return true
    }

    private func logNew() {
        let configure: (LogEvent) -> Void = { [self] event in
            applyEdits(to: event)
        }
        let event = if draft.isTimed, kind.canRun {
            events.startTimed(kind, at: draft.startedAt, configure: configure)
        } else {
            events.log(kind, at: draft.startedAt, configure: configure)
        }
        guard event != nil else {
            saveError = "Your log was not saved. Please try again."
            return
        }
        Haptics.logged()
        dismiss()
    }

    /// Sets only what differs, so an untouched entry is not marked changed
    /// and never re-uploads.
    private func applyEdits(to event: LogEvent) {
        func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<LogEvent, Value>, _ value: Value) {
            if event[keyPath: keyPath] != value { event[keyPath: keyPath] = value }
        }
        set(\.startedAt, draft.startedAt)
        if kind == .feed, event.feedSides != draft.sides { event.feedSides = draft.sides }
        if kind == .feed || kind == .weight { set(\.amount, draft.amount) }
        if kind == .dirty { set(\.stoolColor, draft.stool?.rawValue) }
        if kind.canRun {
            let ended: Date? = draft.isTimed ? nil : draft.startedAt.addingTimeInterval(Double(draft.durationMinutes) * 60)
            set(\.endedAt, ended)
        }
        let trimmed = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        set(\.note, trimmed.isEmpty ? nil : trimmed)
    }
}

/// The kinds a hand-entered row can be, for History's add button and the
/// older-entry link on Now. The editor opens at the current time to adjust.
struct NewEntryMenuItems: View {
    @EnvironmentObject private var settings: BabySettings
    @Binding var editor: EditorRequest?

    var body: some View {
        ForEach(settings.tracked.buttons, id: \.self) { kind in
            Button(kind.isDiaper ? "\(kind.label) diaper" : kind.label) { editor = EditorRequest(kind: kind) }
        }
        Button("Weight") { editor = EditorRequest(kind: .weight) }
    }
}

/// Two wheels, in the units the scale at the pediatrician's office reads:
/// pounds and half ounces in the US, kilograms and ten grams elsewhere.
/// The log keeps grams either way.
private struct WeightPicker: View {
    @Binding var grams: Double

    var body: some View {
        HStack(spacing: 0) {
            if Format.usesImperial {
                wheel("Pounds", selection: pounds, values: Array(1...30)) { "\($0) lb" }
                wheel("Ounces", selection: halfOunces, values: Array(0...31)) {
                    "\((Double($0) / 2).formatted(.number.precision(.fractionLength(0...1)))) oz"
                }
            } else {
                wheel("Kilograms", selection: kilograms, values: Array(0...20)) { "\($0) kg" }
                wheel("Grams", selection: tensOfGrams, values: Array(0...99)) { "\($0 * 10) g" }
            }
        }
        .frame(height: 150)
    }

    private func wheel(_ label: String, selection: Binding<Int>, values: [Int], text: @escaping (Int) -> String) -> some View {
        Picker(label, selection: selection) {
            ForEach(values, id: \.self) { Text(text($0)).tag($0) }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private var totalHalfOunces: Int { Int((grams / Format.gramsPerOunce * 2).rounded()) }

    private var pounds: Binding<Int> {
        Binding(get: { totalHalfOunces / 32 }, set: { setHalfOunces($0 * 32 + totalHalfOunces % 32) })
    }

    private var halfOunces: Binding<Int> {
        Binding(get: { totalHalfOunces % 32 }, set: { setHalfOunces(totalHalfOunces / 32 * 32 + $0) })
    }

    private func setHalfOunces(_ value: Int) {
        grams = Double(value) / 2 * Format.gramsPerOunce
    }

    private var totalTens: Int { Int((grams / 10).rounded()) }

    private var kilograms: Binding<Int> {
        Binding(get: { totalTens / 100 }, set: { grams = Double($0 * 100 + totalTens % 100) * 10 })
    }

    private var tensOfGrams: Binding<Int> {
        Binding(get: { totalTens % 100 }, set: { grams = Double(totalTens / 100 * 100 + $0) * 10 })
    }
}
