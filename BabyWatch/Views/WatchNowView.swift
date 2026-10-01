import SwiftUI

/// The wrist: when she last ate and which side, the last diaper, then the
/// taps. Everything reachable with one thumb on a 3am check.
struct WatchNowView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @EnvironmentObject private var store: WatchStore
    @State private var showsEarlier = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            ScrollView {
                VStack(spacing: AppTheme.tightSpacing) {
                    if !store.hasHeardFromPhone {
                        Text("Open Baby Tracker on your iPhone to connect")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    WatchGlance(summary: store.summary, now: context.date)
                        .padding(.horizontal, AppTheme.hairSpacing)
                    WatchLogGrid(now: context.date)
                        .opacity(isLuminanceReduced ? AppTheme.watchDimmedOpacity : 1)
                    if store.waitingCount > 0 {
                        Label("\(store.waitingCount) waiting for iPhone", systemImage: "iphone.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.ink3)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsEarlier = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Log earlier")
            }
        }
        .sheet(isPresented: $showsEarlier) {
            WatchEarlierView()
        }
    }
}
