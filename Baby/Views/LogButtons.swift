import SwiftUI

/// The four buttons. They never move, never rename, and never gain a fifth:
/// a stable layout is the feature. A tap logs now; a long press opens the
/// editor with that kind pre-filled.
struct LogButtons: View {
    @EnvironmentObject private var events: EventStore
    let onEdit: (EventKind, FeedSide?) -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacing) {
            feedRow
            HStack(spacing: AppTheme.spacing) {
                kindButton(.wet, label: "Wet") { events.log(.wet) }
                kindButton(.dirty, label: "Dirty") { events.log(.dirty) }
            }
            kindButton(.sleep, label: events.runningSleep == nil ? "Sleep" : "Wake", symbol: events.runningSleep == nil ? "moon.fill" : "sun.max.fill") {
                events.toggleSleep()
            }
        }
    }

    /// Feed is one card with three zones so "which side" is answered by the
    /// tap itself, not by a second sheet.
    private var feedRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(FeedSide.allCases.enumerated()), id: \.element) { index, side in
                Button {
                    Haptics.logged()
                    events.log(.feed, side: side)
                } label: {
                    VStack(spacing: AppTheme.hairSpacing) {
                        Text(side.label)
                            .font(.title3.weight(.semibold))
                        Text("Feed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.logButtonHeight)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(AppTheme.ink)
                .pressableCard()
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    Haptics.selected()
                    onEdit(.feed, side)
                })
                .accessibilityLabel("Feed, \(side.label)")
                .accessibilityIdentifier("log.feed.\(side.rawValue)")
                if index < FeedSide.allCases.count - 1 {
                    Rectangle()
                        .fill(AppTheme.feed.opacity(0.35))
                        .frame(width: 1, height: AppTheme.logButtonHeight - AppTheme.looseSpacing)
                }
            }
        }
        .background(AppTheme.fill(for: .feed), in: AppTheme.buttonShape)
        .overlay(alignment: .topLeading) {
            Image(systemName: EventKind.feed.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.feed)
                .padding(AppTheme.tightSpacing)
        }
    }

    private func kindButton(_ kind: EventKind, label: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.logged()
            action()
        } label: {
            HStack(spacing: AppTheme.tightSpacing) {
                Image(systemName: symbol ?? kind.symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.color(for: kind))
                Text(label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.logButtonHeight)
            .background(AppTheme.fill(for: kind), in: AppTheme.buttonShape)
            .contentShape(AppTheme.buttonShape)
        }
        .pressableCard()
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            Haptics.selected()
            onEdit(kind, nil)
        })
        .accessibilityLabel(label)
        .accessibilityIdentifier("log.\(kind.rawValue)")
    }
}
