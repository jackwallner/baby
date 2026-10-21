package com.jackwallner.baby.model

import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.ceil

/** The answer to the 3am question, computed once and shown on Now. Port of iOS `NowSummary`. */
data class NowSummary(
    val childName: String = "Baby",
    val childId: String? = null,
    val dayOfLife: Int? = null,
    val lastFeedAt: Long? = null,
    val lastFeedSides: List<FeedSide> = emptyList(),
    val lastDiaperAt: Long? = null,
    val lastDiaperKind: EventKind? = null,
    val runningSleepStart: Long? = null,
    val lastWokeAt: Long? = null,
    val runningFeedStart: Long? = null,
    val runningFeedSides: List<FeedSide> = emptyList(),
    val todayFeeds: Int = 0,
    val todayWet: Int = 0,
    val todayDirty: Int = 0,
    val tracked: TrackedKinds = TrackedKinds.ALL,
    val words: DiaperWords = DiaperWords.PEE_POOP,
    val recent: List<RecentEntry> = emptyList(),
) {
    val isSleeping: Boolean get() = runningSleepStart != null
    val isFeeding: Boolean get() = runningFeedStart != null

    /** The breast to start on next: the other one from where the last breastfeed ended. */
    val nextBreastSide: FeedSide?
        get() {
            val feeds = listOf(lastFeedSides) + recent.filter { it.kind == EventKind.FEED }.map { it.sides }
            for (sides in feeds) {
                sides.lastOrNull { it != FeedSide.BOTTLE }?.let { return it.next }
            }
            return null
        }

    /** "Start on Right", between feeds only. */
    val nextSideLine: String?
        get() = if (isFeeding) null else nextBreastSide?.let { "Start on ${it.label}" }

    fun feedLine(now: Long): String {
        runningFeedStart?.let { start ->
            val side = FeedSide.label(runningFeedSides)?.let { " · $it" } ?: ""
            return "Feeding$side · ${Format.compactDuration((now - start) / 1000.0)}"
        }
        val last = lastFeedAt ?: return "No feed logged yet"
        val side = FeedSide.label(lastFeedSides)?.let { " · $it" } ?: ""
        return "Fed ${Format.ago(last, now)}$side"
    }

    fun diaperLine(now: Long): String {
        val last = lastDiaperAt ?: return "No diaper logged yet"
        val kind = lastDiaperKind?.let { " · ${it.label(words)}" } ?: ""
        return "Last diaper ${Format.ago(last, now)}$kind"
    }

    fun sleepLine(now: Long): String? = runningSleepStart?.let { Format.asleep((now - it) / 1000.0) }

    fun awakeLine(now: Long): String {
        sleepLine(now)?.let { return it }
        val woke = lastWokeAt ?: return "No sleep logged yet"
        return "Awake ${Format.compactDuration((now - woke) / 1000.0)}"
    }

    /** The last feed, or the last diaper for a family that does not log feeds, or sleep. */
    val leadKind: EventKind
        get() {
            if (tracked.contains(EventKind.FEED)) return EventKind.FEED
            if (!tracked.tracksDiapers) return EventKind.SLEEP
            return lastDiaperKind ?: if (tracked.contains(EventKind.WET)) EventKind.WET else EventKind.DIRTY
        }

    fun leadLine(now: Long): String = when (leadKind) {
        EventKind.FEED -> feedLine(now)
        EventKind.SLEEP -> awakeLine(now)
        else -> diaperLine(now)
    }

    fun supportingLines(now: Long): List<String> {
        val lines = mutableListOf<String>()
        if (leadKind == EventKind.FEED && tracked.tracksDiapers) lines += diaperLine(now)
        if (leadKind != EventKind.SLEEP && tracked.contains(EventKind.SLEEP)) sleepLine(now)?.let(lines::add)
        return lines
    }

    fun leadElapsed(now: Long): String {
        val since = when (leadKind) {
            EventKind.FEED -> runningFeedStart ?: lastFeedAt
            EventKind.SLEEP -> runningSleepStart ?: lastWokeAt
            else -> lastDiaperAt
        } ?: return "–"
        return Format.compactDuration((now - since) / 1000.0)
    }

    /** "7 feeds · 3 pee · 2 poop", only the kinds this family tracks. */
    val todayLine: String
        get() {
            val parts = mutableListOf<String>()
            if (tracked.contains(EventKind.FEED)) parts += Format.count(todayFeeds, "feed")
            if (tracked.contains(EventKind.WET)) parts += "$todayWet ${EventKind.WET.label(words).lowercase()}"
            if (tracked.contains(EventKind.DIRTY)) parts += "$todayDirty ${EventKind.DIRTY.label(words).lowercase()}"
            return parts.joinToString(" · ")
        }

    companion object {
        const val RECENT_LIMIT = 24

        /** Pure: derives the summary from the events list so tests can pin it. */
        fun make(
            child: Child?,
            events: List<LogEvent>,
            now: Long,
            zone: ZoneId,
            window: TotalsWindow,
            tracked: TrackedKinds,
            words: DiaperWords = DiaperWords.PEE_POOP,
        ): NowSummary {
            if (child == null) return NowSummary(tracked = tracked, words = words)
            val visible = events.filter { tracked.contains(it.kind) }
            val today = window.interval(now, zone)
            val sorted = visible.sortedByDescending { it.start }
            var lastFeedAt: Long? = null
            var lastFeedSides = emptyList<FeedSide>()
            var lastDiaperAt: Long? = null
            var lastDiaperKind: EventKind? = null
            var runningSleepStart: Long? = null
            var lastWokeAt: Long? = null
            var runningFeedStart: Long? = null
            var runningFeedSides = emptyList<FeedSide>()
            var feeds = 0
            var wet = 0
            var dirty = 0
            for (event in sorted) {
                when (event.kind) {
                    EventKind.FEED -> if (event.isRunning && runningFeedStart == null) {
                        runningFeedStart = event.startedAt
                        runningFeedSides = event.feedSides
                    } else if (lastFeedAt == null && !event.isRunning) {
                        lastFeedAt = event.startedAt
                        lastFeedSides = event.feedSides
                    }
                    EventKind.WET, EventKind.DIRTY -> if (lastDiaperAt == null) {
                        lastDiaperAt = event.startedAt
                        lastDiaperKind = event.kind
                    }
                    // Newest first, so this keeps the earliest open sleep.
                    EventKind.SLEEP -> if (event.isRunning) {
                        runningSleepStart = event.startedAt
                    } else if (lastWokeAt == null) {
                        lastWokeAt = event.endedAt
                    }
                    EventKind.WEIGHT -> Unit
                }
                if (window.holds(event.start, today)) {
                    when (event.kind) {
                        EventKind.FEED -> feeds++
                        EventKind.WET -> wet++
                        EventKind.DIRTY -> dirty++
                        else -> Unit
                    }
                }
            }
            // A running feed still counts as the most recent feed for "which side".
            val running = runningFeedStart
            if (running != null && running >= (lastFeedAt ?: Long.MIN_VALUE)) {
                lastFeedAt = running
                lastFeedSides = runningFeedSides
            }
            return NowSummary(
                childName = child.displayName,
                childId = child.id,
                dayOfLife = child.dayOfLife(now, zone),
                lastFeedAt = lastFeedAt,
                lastFeedSides = lastFeedSides,
                lastDiaperAt = lastDiaperAt,
                lastDiaperKind = lastDiaperKind,
                runningSleepStart = runningSleepStart,
                lastWokeAt = lastWokeAt,
                runningFeedStart = runningFeedStart,
                runningFeedSides = runningFeedSides,
                todayFeeds = feeds,
                todayWet = wet,
                todayDirty = dirty,
                tracked = tracked,
                words = words,
                recent = sorted.asSequence().filter { it.kind != EventKind.WEIGHT }.map(RecentEntry::from).take(RECENT_LIMIT).toList(),
            )
        }
    }
}

/** One entry as a short list shows it. */
data class RecentEntry(val id: String, val kind: EventKind, val at: Long, val endedAt: Long?, val sides: List<FeedSide>) {
    val isRunning: Boolean get() = kind.canRun && endedAt == null

    /** "Feed · Left", "Pee", "Sleep · 1h 05m", "Asleep". */
    fun title(words: DiaperWords): String = when (kind) {
        EventKind.FEED -> {
            val sideText = FeedSide.label(sides)?.let { " · $it" } ?: ""
            val end = endedAt
            if (end != null && (end - at) / 1000.0 >= 60) "Feed$sideText · ${Format.compactDuration((end - at) / 1000.0)}"
            else if (isRunning) "Feeding$sideText" else "Feed$sideText"
        }
        EventKind.SLEEP -> endedAt?.let { "Sleep · ${Format.duration((it - at) / 1000.0)}" } ?: "Asleep"
        else -> kind.label(words)
    }

    companion object {
        fun from(event: LogEvent) = RecentEntry(
            event.id, event.kind, event.start, event.endedAt,
            if (event.kind == EventKind.FEED) event.feedSides else emptyList(),
        )
    }
}

/** A half-open span of epoch millis. */
data class Span(val start: Long, val end: Long)

/** Per-day totals for the tally and the history headers. */
data class DayTally(
    val feeds: Int = 0,
    val wet: Int = 0,
    val dirty: Int = 0,
    val sleepSeconds: Double = 0.0,
    val bottleMillilitres: Double = 0.0,
) {
    companion object {
        fun make(events: List<LogEvent>, day: Long, now: Long, zone: ZoneId): DayTally {
            val dayStart = DateHelpers.startOfDay(day, zone)
            val dayEnd = DateHelpers.addDays(dayStart, 1, zone)
            var feeds = 0
            var wet = 0
            var dirty = 0
            var bottle = 0.0
            val sleeps = mutableListOf<Span>()
            for (event in events) {
                val start = event.start
                val inDay = start in dayStart until dayEnd
                when (event.kind) {
                    EventKind.FEED -> if (inDay) {
                        feeds++
                        if (FeedSide.BOTTLE in event.feedSides) bottle += maxOf(0.0, event.amount)
                    }
                    EventKind.WET -> if (inDay) wet++
                    EventKind.DIRTY -> if (inDay) dirty++
                    EventKind.SLEEP -> {
                        // Sleep is credited to the day it happened in, split at midnight,
                        // and never past now: an entry set to end later counts so far.
                        val end = minOf(event.endedAt ?: if (event.isRunning) now else start, maxOf(now, start))
                        val overlapStart = maxOf(start, dayStart)
                        val overlapEnd = minOf(end, dayEnd)
                        if (overlapEnd > overlapStart) sleeps += Span(overlapStart, overlapEnd)
                    }
                    EventKind.WEIGHT -> Unit
                }
            }
            return DayTally(feeds, wet, dirty, coveredSeconds(sleeps), bottle)
        }

        /** Time covered by the intervals, counting overlaps once. */
        fun coveredSeconds(intervals: List<Span>): Double =
            coveredIntervals(intervals).sumOf { (it.end - it.start) / 1000.0 }

        /** Merges simultaneous or back-to-back entries into individual bouts. */
        fun coveredIntervals(intervals: List<Span>): List<Span> {
            val covered = mutableListOf<Span>()
            for (interval in intervals.sortedBy { it.start }) {
                val last = covered.lastOrNull()
                if (last != null && interval.start <= last.end) {
                    covered[covered.size - 1] = Span(last.start, maxOf(last.end, interval.end))
                } else {
                    covered += interval
                }
            }
            return covered
        }
    }
}

/** What "today" means for the totals under the log buttons. */
sealed class TotalsWindow {
    data class Day(val startHour: Int) : TotalsWindow()
    data object Last24Hours : TotalsWindow()

    val storedValue: Int get() = when (this) {
        is Day -> startHour
        Last24Hours -> -1
    }

    fun interval(now: Long, zone: ZoneId): Span = when (this) {
        Last24Hours -> Span(now - 24 * 3600 * 1000L, now)
        is Day -> {
            val nowZoned = DateHelpers.zoned(now, zone)
            val today: ZonedDateTime = nowZoned.withHour(startHour).withMinute(0).withSecond(0).withNano(0)
            val start = if (!today.isAfter(nowZoned)) today else today.minusDays(1)
            Span(start.toInstant().toEpochMilli(), start.plusDays(1).toInstant().toEpochMilli())
        }
    }

    /** A day ends where the next one starts; the last 24 hours has no future edge. */
    fun holds(date: Long, interval: Span): Boolean = when (this) {
        is Day -> date >= interval.start && date < interval.end
        Last24Hours -> date >= interval.start
    }

    fun title(locale: java.util.Locale = java.util.Locale.getDefault()): String = when (this) {
        Last24Hours -> "Last 24 hours"
        is Day -> if (startHour == 0) "Today" else "Since ${Format.hourLabel(startHour, locale)}"
    }

    companion object {
        val MIDNIGHT = Day(0)

        fun fromStored(value: Int?): TotalsWindow = when {
            value == -1 -> Last24Hours
            value != null && value in 0..23 -> Day(value)
            else -> MIDNIGHT
        }
    }
}

/** The totals under the log buttons and the hour strip beneath them, from one pass. */
data class WindowTotals(
    val interval: Span,
    val gridStart: Long,
    val feeds: Int,
    val wet: Int,
    val dirty: Int,
    val sleepSeconds: Double,
    val hours: Map<EventKind, List<Double>>,
    val futureFrom: Int,
) {
    fun count(kind: EventKind): Int = when (kind) {
        EventKind.FEED -> feeds
        EventKind.WET -> wet
        EventKind.DIRTY -> dirty
        else -> 0
    }

    /** "7 feeds · 3 pee · 2 poop · 5h 10m sleep", for the buttons this family uses. */
    fun line(tracked: TrackedKinds, words: DiaperWords): String {
        val parts = mutableListOf<String>()
        if (tracked.contains(EventKind.FEED)) parts += Format.count(feeds, "feed")
        if (tracked.contains(EventKind.WET)) parts += "$wet ${EventKind.WET.label(words).lowercase()}"
        if (tracked.contains(EventKind.DIRTY)) parts += "$dirty ${EventKind.DIRTY.label(words).lowercase()}"
        if (tracked.contains(EventKind.SLEEP) && sleepSeconds >= 60) parts += "${Format.compactDuration(sleepSeconds)} sleep"
        return parts.joinToString(" · ")
    }

    companion object {
        val KINDS = listOf(EventKind.FEED, EventKind.WET, EventKind.DIRTY, EventKind.SLEEP)
        const val COLUMNS = 24
        private const val HOUR = 3600_000L

        fun make(events: List<LogEvent>, window: TotalsWindow, now: Long, zone: ZoneId): WindowTotals {
            val interval = window.interval(now, zone)
            val start = when (window) {
                is TotalsWindow.Day -> interval.start
                TotalsWindow.Last24Hours -> {
                    val hourStart = DateHelpers.zoned(now, zone).withMinute(0).withSecond(0).withNano(0).toInstant().toEpochMilli()
                    hourStart - (COLUMNS - 1) * HOUR
                }
            }
            val hours = KINDS.associateWith { DoubleArray(COLUMNS) }
            fun column(date: Long): Int? {
                val index = ((date - start) / 3600_000.0).toInt()
                return if (index in 0 until COLUMNS) index else null
            }
            var feeds = 0
            var wet = 0
            var dirty = 0
            val sleeps = mutableListOf<Span>()
            for (event in events) {
                val at = event.start
                when (event.kind) {
                    EventKind.FEED, EventKind.WET, EventKind.DIRTY -> {
                        if (!window.holds(at, interval)) continue
                        when (event.kind) {
                            EventKind.FEED -> feeds++
                            EventKind.WET -> wet++
                            else -> dirty++
                        }
                        column(at)?.let { hours.getValue(event.kind)[it] += 1.0 }
                    }
                    EventKind.SLEEP -> {
                        val end = minOf(event.endedAt ?: if (event.isRunning) now else at, now)
                        val clippedStart = maxOf(at, minOf(interval.start, start))
                        val clippedEnd = minOf(end, interval.end)
                        if (clippedEnd > clippedStart) sleeps += Span(clippedStart, clippedEnd)
                    }
                    EventKind.WEIGHT -> Unit
                }
            }
            var sleepSeconds = 0.0
            for (bout in DayTally.coveredIntervals(sleeps)) {
                val counted = (minOf(bout.end, interval.end) - maxOf(bout.start, interval.start)) / 1000.0
                if (counted > 0) sleepSeconds += counted
                for (index in 0 until COLUMNS) {
                    val hourStart = start + index * HOUR
                    val overlap = (minOf(bout.end, hourStart + HOUR) - maxOf(bout.start, hourStart)) / 1000.0
                    if (overlap > 0) hours.getValue(EventKind.SLEEP)[index] += overlap / 3600
                }
            }
            val futureFrom = maxOf(0, minOf(COLUMNS, ceil((now - start) / 3600_000.0).toInt()))
            return WindowTotals(interval, start, feeds, wet, dirty, sleepSeconds, hours.mapValues { it.value.toList() }, futureFrom)
        }
    }
}
