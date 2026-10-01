import SwiftUI

/// Log earlier: turn the crown back to when it happened, then tap. For the
/// feed remembered twenty minutes later.
struct WatchEarlierView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutesAgo = 15

    /// Five-minute steps for the first hour, then quarter hours to six hours.
    static let steps: [Int] = Array(stride(from: 5, through: 60, by: 5)) + Array(stride(from: 75, through: 360, by: 15))

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let at = context.date.addingTimeInterval(-Double(minutesAgo) * 60)
            ScrollView {
                VStack(spacing: AppTheme.tightSpacing) {
                    Picker("When", selection: $minutesAgo) {
                        ForEach(Self.steps, id: \.self) { minutes in
                            Text("\(Format.compactDuration(Double(minutes) * 60)) ago").tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: AppTheme.watchWheelHeight)
                    Text("At \(Format.time(at))")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ink2)
                    WatchLogGrid(now: context.date, at: at) { dismiss() }
                }
            }
        }
        .navigationTitle("Log earlier")
    }
}
