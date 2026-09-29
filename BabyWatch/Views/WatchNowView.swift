import SwiftUI

/// The wrist: the last feed and diaper, then up to six taps. Nothing to scroll for
/// on a 3am check, everything reachable with one thumb.
struct WatchNowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: WatchStore
    @State private var now = Date.now

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.hairSpacing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.summary.leadKind.isDiaper ? diaperLine : store.summary.leadLine(now: now))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if store.summary.leadKind == .feed, tracked.tracksDiapers {
                        Text(diaperLine)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.ink2)
                            .lineLimit(2)
                    }
                    if store.summary.leadKind != .sleep, tracked.contains(.sleep), let sleep = store.summary.sleepLine(now: now) {
                        Text(sleep)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.sleep)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.hairSpacing)

                // The phone's buttons, minus any turned off in its Settings.
                if tracked.contains(.feed) {
                    HStack(spacing: AppTheme.hairSpacing) {
                        ForEach(FeedSide.allCases, id: \.self) { side in
                            logButton(side.shortLabel, kind: .feed) { store.log(.feed, side: side) }
                        }
                    }
                }
                if tracked.tracksDiapers {
                    HStack(spacing: AppTheme.hairSpacing) {
                        if tracked.contains(.wet) { logButton(EventKind.wet.label, kind: .wet) { store.log(.wet) } }
                        if tracked.contains(.dirty) { logButton(EventKind.dirty.label, kind: .dirty) { store.log(.dirty) } }
                    }
                }
                if tracked.contains(.sleep) {
                    logButton(store.summary.isSleeping ? "Wake" : "Sleep", kind: .sleep) { store.toggleSleep() }
                }

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
        .toolbarTitleDisplayMode(.inline)
        .onReceive(clock) { now = $0 }
        .animation(reduceMotion ? nil : .default, value: store.lastAction)
    }

    private var tracked: TrackedKinds { store.summary.tracked }

    private var diaperLine: String {
        guard let date = store.summary.lastDiaperAt else { return "No diaper logged yet" }
        let kind = store.summary.lastDiaperKind.map { " · \($0.label)" } ?? ""
        return "Diaper \(Format.ago(date, now: now))\(kind)"
    }

    private func logButton(_ label: String, kind: EventKind, action: @escaping () -> Void) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            HStack(spacing: AppTheme.hairSpacing) {
                if kind != .feed {
                    Image(systemName: kind == .sleep && store.summary.isSleeping ? "sun.max" : kind.symbolName)
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(label).font(.headline)
            }
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(AppTheme.buttonShape)
        }
        .buttonStyle(.plain)
        .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
        .overlay(AppTheme.buttonShape.strokeBorder(AppTheme.outline, lineWidth: AppTheme.outlineWidth))
    }
}
