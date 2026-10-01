#if DEBUG
import SwiftUI
import WidgetKit

/// `-ComplicationGallery`: every complication face at its 45mm size, drawn
/// from the live summary, so a UI test can look at them without a watch face.
struct ComplicationGallery: View {
    @EnvironmentObject private var store: WatchStore

    private let circular = CGSize(width: 50, height: 50)
    private let rectangular = CGSize(width: 184, height: 64)

    var body: some View {
        let entry = WatchBabyEntry(date: .now, summary: store.summary)
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                HStack(spacing: AppTheme.tightSpacing) {
                    LastFeedView(familyOverride: .accessoryCircular, entry: entry).frame(width: circular.width, height: circular.height)
                    LastDiaperView(familyOverride: .accessoryCircular, entry: entry).frame(width: circular.width, height: circular.height)
                    SleepToggleView(familyOverride: .accessoryCircular, entry: entry).frame(width: circular.width, height: circular.height)
                }
                HStack(spacing: AppTheme.tightSpacing) {
                    LogDiaperView(familyOverride: .accessoryCircular, entry: entry, kind: .wet).frame(width: circular.width, height: circular.height)
                    LogDiaperView(familyOverride: .accessoryCircular, entry: entry, kind: .dirty).frame(width: circular.width, height: circular.height)
                }
                LastFeedView(familyOverride: .accessoryRectangular, entry: entry).frame(width: rectangular.width, height: rectangular.height)
                LastDiaperView(familyOverride: .accessoryRectangular, entry: entry).frame(width: rectangular.width, height: rectangular.height)
                LastFeedView(familyOverride: .accessoryInline, entry: entry).lineLimit(1)
            }
        }
    }
}
#endif
