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
                        LabeledContent("Time") {
                            DatePicker("Time", selection: $startedAt, in: ...Date.now.addingTimeInterval(60))
                                .labelsHidden()
                                .themedDatePicker()
                        }
                    }
                    if kind == .feed {
                        Section("Feed") {
                            Picker("Side", selection: $side) {
                                ForEach(FeedSide.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if side == .bottle {
                                Stepper("Amount: \(Format.millilitres(amount))", value: $amount, in: 0...400,
                                        step: Format.usesImperial ? Format.millilitresPerOunce / 2 : 10)
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
                            WeightPicker(grams: $amount)
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
                .themedRow()
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
        .onAppear {
            if kind == .weight, amount <= 0 { amount = startingWeight }
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
        case .wet, .dirty: isNew ? "Log a \(kind.label.lowercased()) diaper" : "\(kind.label) diaper"
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
