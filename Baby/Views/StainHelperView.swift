import SwiftUI

/// Opened from the undo toast after a dirty diaper, and from a quiet row on
/// Now. Never from the four buttons, which do not move.
struct StainHelperView: View {
    @Environment(\.dismiss) private var dismiss

    var initialStain: StainGuide.Stain = .blowout

    @State private var stain: StainGuide.Stain = .blowout
    @State private var supplies: Set<StainGuide.Supply> = StainGuide.storedSupplies()
    @State private var isEditingSupplies = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                    if isEditingSupplies || !StainGuide.hasChosenSupplies {
                        suppliesPicker
                    } else {
                        stainPicker
                        firstMove
                        steps
                        suppliesFooter
                    }
                }
                .padding(.horizontal, AppTheme.margin)
                .padding(.vertical, AppTheme.spacing)
            }
            .background(AppTheme.paper)
            .navigationTitle("Stain helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditingSupplies ? "Done" : "Close") {
                        if isEditingSupplies {
                            StainGuide.store(supplies)
                            isEditingSupplies = false
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { stain = initialStain }
        }
    }

    // MARK: - Setup

    private var suppliesPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            Text("What do you have at home?")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
            Text("Asked once. The steps then skip anything you do not have, instead of sending you to the shop at 2am.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(StainGuide.Supply.allCases) { supply in
                Button {
                    if supplies.contains(supply) { supplies.remove(supply) } else { supplies.insert(supply) }
                    Haptics.selected()
                    StainGuide.store(supplies)
                } label: {
                    HStack(spacing: AppTheme.spacing) {
                        Image(systemName: supplies.contains(supply) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(supplies.contains(supply) ? AppTheme.accent : AppTheme.ink3)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(supply.label)
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppTheme.ink)
                            Text(supply.hint)
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink2)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .pressableCard()
            }
            Button("Save") {
                StainGuide.store(supplies)
                isEditingSupplies = false
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - Steps

    private var stainPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            SectionLabel(text: "What happened")
            Picker("What happened", selection: $stain) {
                ForEach(StainGuide.Stain.allCases) { stain in
                    Text(stain.label).tag(stain)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var firstMove: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            HStack(spacing: AppTheme.tightSpacing) {
                Image(systemName: stain.symbolName)
                    .foregroundStyle(AppTheme.accent)
                Text("Right now")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
            }
            Text(stain.firstMove)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(StainGuide.careLabelRule)
                .font(.caption)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            SectionLabel(text: "Then, in this order")
            ForEach(Array(StainGuide.steps(for: stain, owning: supplies).enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: AppTheme.spacing) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                        Text(step.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(step.detail)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let caution = step.caution {
                            Text(caution)
                                .font(.caption)
                                .foregroundStyle(AppTheme.notice)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            let missing = StainGuide.missing(for: stain, owning: supplies)
            if !missing.isEmpty {
                Text("Would also work: \(missing.map(\.label).joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(StainGuide.neverRule)
                .font(.caption)
                .foregroundStyle(AppTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var suppliesFooter: some View {
        Button("Change what you have at home") { isEditingSupplies = true }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(minHeight: 44)
    }
}
