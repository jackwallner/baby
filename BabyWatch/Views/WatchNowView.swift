import SwiftUI

/// The wrist: the last feed and diaper, then six taps. Nothing to scroll for
/// on a 3am check, everything reachable with one thumb.
struct WatchNowView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var now = Date.now

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.tightSpacing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.summary.feedLine(now: now))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(store.summary.diaperLine(now: now))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ink2)
                        .lineLimit(2)
                    if let sleep = store.summary.sleepLine(now: now) {
                        Text(sleep)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.sleep)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.hairSpacing)

                HStack(spacing: AppTheme.hairSpacing) {
                    ForEach(FeedSide.allCases, id: \.self) { side in
                        logButton(side.shortLabel, kind: .feed) { store.log(.feed, side: side) }
                    }
                }
                HStack(spacing: AppTheme.hairSpacing) {
                    logButton("Wet", kind: .wet) { store.log(.wet) }
                    logButton("Dirty", kind: .dirty) { store.log(.dirty) }
                }
                logButton(store.summary.isSleeping ? "Wake" : "Sleep", kind: .sleep) { store.toggleSleep() }

                if let action = store.lastAction {
                    Text(action)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ink2)
                        .transition(.opacity)
                }
                if !store.pending.isEmpty {
                    Text("\(store.pending.count) waiting for iPhone")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ink3)
                }
            }
        }
        .navigationTitle(store.summary.childName)
        .onReceive(clock) { now = $0 }
        .animation(.default, value: store.lastAction)
    }

    private func logButton(_ label: String, kind: EventKind, action: @escaping () -> Void) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            Text(label)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
        .overlay(AppTheme.buttonShape.stroke(AppTheme.color(for: kind).opacity(0.5), lineWidth: 1))
    }
}
