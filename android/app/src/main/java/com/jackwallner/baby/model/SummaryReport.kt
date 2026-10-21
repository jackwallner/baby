package com.jackwallner.baby.model

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs

/**
 * Everything the pediatrician summary, the trends and the CSV are built from,
 * derived once from the log so the PDF, the charts and the export can never
 * disagree. Port of iOS `SummaryReport`; pinned by golden.json.
 */
data class SummaryReport(
    val childName: String,
    val birthDate: Long?,
    val start: Long,
    val end: Long,
    val days: List<Day>,
    val notes: List<Pair<Long, String>>,
    val tracked: TrackedKinds,
    val zone: ZoneId,
) {
    sealed class Partial {
        data class LoggingBegan(val at: Long) : Partial()
        data object Today : Partial()
        data object NothingLogged : Partial()

        fun label(zone: ZoneId, locale: Locale = Locale.getDefault()): String = when (this) {
            is LoggingBegan -> "from ${Format.time(at, zone, locale)}"
            Today -> "so far"
            NothingLogged -> "not logged"
        }
    }

    data class Day(
        val date: Long,
        val dayOfLife: Int?,
        val feeds: Int,
        val wet: Int,
        val dirty: Int,
        val bottleMillilitres: Double,
        val sleepSeconds: Double,
        val longestSleepSeconds: Double,
        val longestFeedGapSeconds: Double,
        val bottleFeeds: Int,
        val weightGrams: Double?,
        val stoolColors: List<StoolColor>,
        val partial: Partial? = null,
    ) {
        val isComplete: Boolean get() = partial == null
        val hasEntries: Boolean get() = feeds > 0 || wet > 0 || dirty > 0 || sleepSeconds > 0
    }

    val dayCount: Int get() = days.size
    val totalFeeds: Int get() = days.sumOf { it.feeds }
    val totalWet: Int get() = days.sumOf { it.wet }
    val totalDirty: Int get() = days.sumOf { it.dirty }

    /** Not today, not the day logging began, not a day with nothing in it. */
    val completeDays: List<Day>
        get() {
            val complete = days.filter { it.isComplete }
            if (complete.isNotEmpty()) return complete
            val logged = days.filter { it.hasEntries }
            return logged.ifEmpty { days }
        }

    val hasCompleteDays: Boolean get() = days.any { it.isComplete }
    val partialDays: List<Day> get() = if (hasCompleteDays) days.filter { !it.isComplete } else emptyList()

    private fun average(value: (Day) -> Int): Double {
        val complete = completeDays
        return if (complete.isEmpty()) 0.0 else complete.sumOf { value(it).toDouble() } / complete.size
    }

    val averageFeedsPerDay: Double get() = average { it.feeds }
    val averageWetPerDay: Double get() = average { it.wet }
    val averageDirtyPerDay: Double get() = average { it.dirty }

    val averageSleepSeconds: Double
        get() {
            val complete = completeDays
            return if (complete.isEmpty()) 0.0 else complete.sumOf { it.sleepSeconds } / complete.size
        }

    val longestSleepSeconds: Double get() = days.maxOfOrNull { it.longestSleepSeconds } ?: 0.0
    val longestFeedGapSeconds: Double get() = days.maxOfOrNull { it.longestFeedGapSeconds } ?: 0.0

    val averageBottleMillilitresPerDay: Double
        get() {
            val bottleDays = completeDays.filter { it.bottleMillilitres > 0 }
            return if (bottleDays.isEmpty()) 0.0 else bottleDays.sumOf { it.bottleMillilitres } / bottleDays.size
        }

    val averageBottleMillilitresPerFeed: Double
        get() {
            val feeds = days.sumOf { it.bottleFeeds }
            return if (feeds <= 0) 0.0 else days.sumOf { it.bottleMillilitres } / feeds
        }

    /** The lowest complete day, which is the day a doctor asks about. */
    fun <T : Comparable<T>> lowestDay(key: (Day) -> T): Day? = completeDays.minByOrNull(key)

    val firstWeight: Double? get() = days.firstNotNullOfOrNull { it.weightGrams }
    val latestWeight: Double? get() = days.lastOrNull { it.weightGrams != null }?.weightGrams
    val firstWeightDate: Long? get() = days.firstOrNull { it.weightGrams != null }?.date

    val weightChangeGrams: Double?
        get() {
            val first = firstWeight ?: return null
            val latest = latestWeight ?: return null
            return if (first == latest) null else latest - first
        }

    val weightChangePercent: Double?
        get() {
            val first = firstWeight ?: return null
            val change = weightChangeGrams ?: return null
            return if (first > 0) change / first * 100 else null
        }

    /** "+210 g (+6.6%) since Sep 29". */
    fun weightChangeDescription(imperial: Boolean, locale: Locale = Locale.getDefault()): String? {
        val change = weightChangeGrams
        val percent = weightChangePercent
        val since = firstWeightDate
        if (change == null || percent == null || since == null) return if (latestWeight == null) null else "One weigh-in"
        val sign = if (percent > 0) "+" else "−"
        return "${Format.gramsChange(change, imperial)} ($sign${Format.oneDecimal(abs(percent))}%) since ${Format.monthDay(since, zone, locale)}"
    }

    /** "Averages use 6 complete days." with the days left out named. */
    fun averagesNote(locale: Locale = Locale.getDefault()): String {
        if (!hasCompleteDays) return "No complete day yet, so averages use every day logged so far."
        var note = "Averages use ${Format.count(completeDays.size, "complete day")}."
        val partial = partialDays
        if (partial.isEmpty()) return note
        val skipped = partial.map { day ->
            when (val p = day.partial) {
                Partial.Today -> "today (so far)"
                is Partial.LoggingBegan -> "${Format.monthDay(day.date, zone, locale)} (logging began ${Format.time(p.at, zone, locale)})"
                else -> Format.monthDay(day.date, zone, locale)
            }
        }
        val unlogged = partial.count { it.partial == Partial.NothingLogged }
        note += when {
            unlogged == partial.size -> " ${Format.count(unlogged, "day")} with nothing logged ${if (unlogged == 1) "is" else "are"} left out."
            skipped.size <= 3 -> " Left out: ${skipped.joinToString(", ")}."
            else -> " ${Format.count(partial.size, "partial or unlogged day")} left out."
        }
        return note
    }

    fun rangeLabel(locale: Locale = Locale.getDefault()): String =
        "${Format.monthDayYear(start, zone, locale)} to ${Format.monthDayYear(end, zone, locale)}"

    companion object {
        /** One row per calendar day from start to end inclusive, including days with nothing logged. */
        fun make(
            childName: String,
            birthDate: Long?,
            events: List<LogEvent>,
            from: Long,
            to: Long,
            tracked: TrackedKinds,
            now: Long,
            zone: ZoneId,
            words: DiaperWords = DiaperWords.WET_DIRTY,
        ): SummaryReport {
            val firstDay = DateHelpers.startOfDay(minOf(from, to), zone)
            val lastDay = DateHelpers.startOfDay(maxOf(from, to), zone)
            val rangeEnd = DateHelpers.addDays(lastDay, 1, zone)
            val lookback = DateHelpers.addDays(firstDay, -1, zone)
            val feedStarts = events.filter { it.kind == EventKind.FEED && it.start >= lookback && it.start < rangeEnd }
                .map { it.start }.sorted()
            val loggingBegan = events.minOfOrNull { it.start }
            val today = DateHelpers.startOfDay(now, zone)
            val inRange = events.filter { event ->
                if (!tracked.contains(event.kind)) return@filter false
                val finish = event.endedAt ?: if (event.isRunning) now else event.start
                event.start < rangeEnd && maxOf(finish, event.start) >= firstDay
            }
            // A gap that spans a whole calendar day is a day nobody logged.
            val feedGaps = feedStarts.zipWithNext().filter { (earlier, later) ->
                DateHelpers.daysBetween(earlier, later, zone) <= 1
            }.map { (earlier, later) -> later to (later - earlier) / 1000.0 }
            val sleepBouts = DayTally.coveredIntervals(inRange.mapNotNull { event ->
                if (event.kind != EventKind.SLEEP) return@mapNotNull null
                val finish = event.endedAt ?: if (event.isRunning) now else event.start
                if (finish > event.start) Span(event.start, finish) else null
            })
            val days = mutableListOf<Day>()
            var cursor = firstDay
            while (cursor <= lastDay) {
                val tally = DayTally.make(inRange, cursor, now, zone)
                val dayEnd = DateHelpers.addDays(cursor, 1, zone)
                val inDay = inRange.filter { it.start in cursor until dayEnd }
                val longest = sleepBouts.filter { it.start in cursor until dayEnd }.maxOfOrNull { (it.end - it.start) / 1000.0 } ?: 0.0
                var day = Day(
                    date = cursor,
                    dayOfLife = birthDate?.let { DateHelpers.dayOfLife(it, cursor, zone) },
                    feeds = tally.feeds,
                    wet = tally.wet,
                    dirty = tally.dirty,
                    bottleMillilitres = tally.bottleMillilitres,
                    sleepSeconds = tally.sleepSeconds,
                    longestSleepSeconds = longest,
                    longestFeedGapSeconds = feedGaps.filter { it.first in cursor until dayEnd }.maxOfOrNull { it.second } ?: 0.0,
                    bottleFeeds = inDay.count { it.kind == EventKind.FEED && FeedSide.BOTTLE in it.feedSides && it.amount > 0 },
                    weightGrams = inDay.filter { it.kind == EventKind.WEIGHT && it.amount > 0 }.map { it.amount }.lastOrNull(),
                    stoolColors = inDay.mapNotNull { if (it.kind == EventKind.DIRTY) it.stool else null },
                )
                day = when {
                    cursor >= today -> day.copy(partial = Partial.Today)
                    loggingBegan != null && loggingBegan >= cursor && loggingBegan < dayEnd -> day.copy(partial = Partial.LoggingBegan(loggingBegan))
                    !day.hasEntries -> day.copy(partial = Partial.NothingLogged)
                    else -> day
                }
                days += day
                cursor = dayEnd
            }
            val notes = inRange.filter { it.start >= firstDay && it.start < rangeEnd }.mapNotNull { event ->
                val note = event.note?.trim()
                if (note.isNullOrEmpty()) null else event.start to "${event.kind.label(words)}: $note"
            }.sortedBy { it.first }
            return SummaryReport(childName, birthDate, firstDay, lastDay, days, notes, tracked, zone)
        }

        const val CSV_HEADER = "baby,date,time,kind,side,amount_ml,weight_g,stool_color,duration_min,note,logged_at"

        /**
         * Every entry as a spreadsheet, oldest first. The date column is the
         * local calendar day; iOS writes it in UTC (see the Android rule).
         */
        fun csv(events: List<LogEvent>, childName: String, zone: ZoneId, locale: Locale = Locale.getDefault()): String {
            val lines = mutableListOf(CSV_HEADER)
            for (event in events.sortedBy { it.start }) {
                val start = event.start
                val duration = event.duration?.let { Format.roundAway(it / 60).toInt().toString() } ?: ""
                val amount = if (event.kind == EventKind.FEED && event.amount > 0) event.amount.toInt().toString() else ""
                val weight = if (event.kind == EventKind.WEIGHT && event.amount > 0) event.amount.toInt().toString() else ""
                val fields = listOf(
                    childName,
                    DateTimeFormatter.ISO_LOCAL_DATE.format(DateHelpers.zoned(start, zone)),
                    Format.time(start, zone, locale),
                    event.kind.raw,
                    event.feedSides.joinToString("+") { it.raw },
                    amount,
                    weight,
                    event.stool?.raw ?: "",
                    duration,
                    event.note ?: "",
                    DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(event.createdAt).truncatedTo(ChronoUnit.SECONDS)),
                )
                lines += fields.joinToString(",", transform = ::escape)
            }
            return lines.joinToString("\n") + "\n"
        }

        /** RFC 4180. */
        private fun escape(field: String): String {
            if (field.none { it == ',' || it == '"' || it == '\n' || it == '\r' }) return field
            return "\"" + field.replace("\"", "\"\"") + "\""
        }
    }
}
