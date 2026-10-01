import SwiftUI
import WidgetKit

// MARK: - Widgets

struct LastFeedComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.complication, provider: WatchBabyProvider()) { entry in
            LastFeedView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last feed")
        .description("How long since the last feed, and which side.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct LastDiaperComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.watchDiaper, provider: WatchBabyProvider()) { entry in
            LastDiaperView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last diaper")
        .description("How long since the last diaper, and today's count.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct LogWetComplication: Widget {
    /// A plain String: WidgetKit traps on an interpolated display name.
    static let name = "Log " + EventKind.wet.label.lowercased()

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.watchLogWet, provider: WatchBabyProvider()) { entry in
            LogDiaperView(entry: entry, kind: .wet)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Self.name)
        .description("One tap on the face logs it, with Undo in the app.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct LogDirtyComplication: Widget {
    static let name = "Log " + EventKind.dirty.label.lowercased()

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.watchLogDirty, provider: WatchBabyProvider()) { entry in
            LogDiaperView(entry: entry, kind: .dirty)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Self.name)
        .description("One tap on the face logs it, with Undo in the app.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct SleepComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.watchSleep, provider: WatchBabyProvider()) { entry in
            SleepToggleView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sleep and wake")
        .description("Starts or ends a sleep in one tap, and shows how long it has run.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

@main
struct BabyWatchWidgets: WidgetBundle {
    var body: some Widget {
        LastFeedComplication()
        LastDiaperComplication()
        LogWetComplication()
        LogDirtyComplication()
        SleepComplication()
    }
}
