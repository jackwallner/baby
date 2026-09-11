import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen and Dynamic Island presentation of a running feed or sleep:
/// the elapsed time, and one Stop button.
struct BabyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BabyActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(AppTheme.card)
                .activitySystemActionForegroundColor(AppTheme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: AppTheme.hairSpacing) {
                        Image(systemName: symbol(context))
                            .foregroundStyle(color(context))
                        Text(title(context))
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(context)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: 72)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    stopButton(context)
                }
            } compactLeading: {
                Image(systemName: symbol(context)).foregroundStyle(color(context))
            } compactTrailing: {
                elapsed(context)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: symbol(context)).foregroundStyle(color(context))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<BabyActivityAttributes>) -> some View {
        HStack(spacing: AppTheme.spacing) {
            Image(systemName: symbol(context))
                .font(.title2.weight(.semibold))
                .foregroundStyle(color(context))
                .frame(width: 44, height: 44)
                .background(color(context).opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title(context))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("\(context.attributes.childName) · since \(Format.time(context.state.startedAt))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink2)
            }
            Spacer(minLength: AppTheme.tightSpacing)
            elapsed(context)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
            stopButton(context)
        }
        .padding(AppTheme.spacing)
    }

    @ViewBuilder
    private func stopButton(_ context: ActivityViewContext<BabyActivityAttributes>) -> some View {
        if #available(iOS 17.2, *) {
            Button(intent: StopRunningIntent(kind: context.attributes.kind)) {
                Text(context.attributes.kind == EventKind.sleep.rawValue ? "Wake" : "Stop")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, AppTheme.spacing)
                    .frame(height: 44)
            }
            .tint(color(context))
        }
    }

    private func elapsed(_ context: ActivityViewContext<BabyActivityAttributes>) -> some View {
        Text(context.state.startedAt, style: .timer)
    }

    private func title(_ context: ActivityViewContext<BabyActivityAttributes>) -> String {
        if context.attributes.kind == EventKind.sleep.rawValue { return "Asleep" }
        if let side = context.attributes.side.flatMap(FeedSide.init(rawValue:)) { return "Feeding · \(side.label)" }
        return "Feeding"
    }

    private func symbol(_ context: ActivityViewContext<BabyActivityAttributes>) -> String {
        context.attributes.kind == EventKind.sleep.rawValue ? EventKind.sleep.symbolName : EventKind.feed.symbolName
    }

    private func color(_ context: ActivityViewContext<BabyActivityAttributes>) -> Color {
        context.attributes.kind == EventKind.sleep.rawValue ? AppTheme.sleep : AppTheme.feed
    }
}
