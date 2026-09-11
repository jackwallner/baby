import ActivityKit
import SwiftUI
import WidgetKit

/// Dynamic Island + lock-screen presentation of a running practice or walk
/// session: live countdown and the current alignment color.
struct PracticeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PracticeActivityAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(Theme.paper)
                .activitySystemActionForegroundColor(Theme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: icon(context))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(color(context))
                        Text(qualityWord(context))
                            .font(Theme.font(.headline, weight: .bold))
                            .foregroundStyle(color(context))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context)
                        .font(Theme.font(.title3, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(maxWidth: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(bottomLine(context))
                        .font(Theme.font(.footnote))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: icon(context))
                    .foregroundStyle(color(context))
            } compactTrailing: {
                countdown(context)
                    .font(Theme.font(.caption2, weight: .semibold))
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: icon(context))
                    .foregroundStyle(color(context))
            }
        }
    }

    // MARK: - Lock screen

    private func lockScreenView(_ context: ActivityViewContext<PracticeActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color(context).opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: icon(context))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(lockColor(context))
            }
            VStack(alignment: .leading, spacing: 2) {
                // Lead with the live posture state, in its own color, so a
                // glance at the lock screen reads "aligned / drifting /
                // slouching" without decoding the icon tint.
                Text(qualityWord(context))
                    .font(Theme.font(.headline, weight: .bold))
                    .foregroundStyle(lockColor(context))
                Text(bottomLine(context))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 8)
            countdown(context)
                .font(Theme.font(.title2, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(16)
    }

    // MARK: - Bits

    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<PracticeActivityAttributes>) -> some View {
        if context.state.paused {
            Text("paused")
        } else {
            Text(timerInterval: Date.now...max(context.state.endDate, .now), countsDown: true)
        }
    }

    private func kindWord(_ context: ActivityViewContext<PracticeActivityAttributes>) -> String {
        context.attributes.kind == "walk" ? "Walk" : "Practice"
    }

    private func bottomLine(_ context: ActivityViewContext<PracticeActivityAttributes>) -> String {
        if context.state.paused { return "Paused. Your minutes are safe." }
        return "\(kindWord(context)) · \(context.state.alignedPercent)% aligned"
    }

    /// The glyph itself carries the posture state, not just its color - the
    /// compact and minimal Dynamic Island are too small (and color alone too
    /// subtle, and colorblind-hostile) to read "tall vs slouched" from a tint.
    /// Each state gets a distinct silhouette: an upright figure when you're
    /// tall, a caution triangle when you drift, a head-down arrow when you
    /// slouch, a pause glyph when stopped.
    private func icon(_ context: ActivityViewContext<PracticeActivityAttributes>) -> String {
        if context.state.paused { return "pause.circle.fill" }
        let walk = context.attributes.kind == "walk"
        switch context.state.quality {
        case "good": return walk ? "figure.walk" : "figure.stand"
        case "borderline": return "exclamationmark.triangle.fill"
        default: return "arrow.down.circle.fill"
        }
    }

    /// Dynamic Island tint: pastels read well on the island's black.
    private func color(_ context: ActivityViewContext<PracticeActivityAttributes>) -> Color {
        if context.state.paused { return Theme.ink3 }
        switch context.state.quality {
        case "good": return Theme.sage
        case "borderline": return Theme.sand
        default: return Theme.clay
        }
    }

    /// Lock-screen tint: the banner sits on the light paper wash, where the
    /// pastels wash out - the state word needs the text-grade colors.
    private func lockColor(_ context: ActivityViewContext<PracticeActivityAttributes>) -> Color {
        if context.state.paused { return Theme.ink3 }
        switch context.state.quality {
        case "good": return Theme.goodText
        case "borderline": return Theme.borderlineText
        default: return Theme.badText
        }
    }

    private func qualityWord(_ context: ActivityViewContext<PracticeActivityAttributes>) -> String {
        if context.state.paused { return "Paused" }
        switch context.state.quality {
        case "good": return context.attributes.kind == "walk" ? "Tall" : "Aligned"
        case "borderline": return "Drifting"
        default: return "Slouching"
        }
    }
}
