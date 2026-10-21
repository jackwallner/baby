package com.jackwallner.baby

import com.jackwallner.baby.model.Child
import com.jackwallner.baby.model.DayTally
import com.jackwallner.baby.model.DiaperWords
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedReminderInterval
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.Guidance
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.model.NowSummary
import com.jackwallner.baby.model.ReminderPlan
import com.jackwallner.baby.model.StainGuide
import com.jackwallner.baby.model.SummaryReport
import com.jackwallner.baby.model.TotalsWindow
import com.jackwallner.baby.model.TrackedKinds
import com.jackwallner.baby.model.WindowTotals
import java.time.ZoneId
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every answer here was computed by the iOS Swift sources themselves
 * (scripts/android-golden/export.sh compiles them), so a transcription slip
 * in the Kotlin port fails the build.
 */
class GoldenParityTest {
    private val golden: JSONObject = JSONObject(
        javaClass.classLoader!!.getResourceAsStream("golden.json")!!.bufferedReader().readText(),
    )
    private val zone: ZoneId = ZoneId.of(golden.getString("zone"))
    private val locale = Locale.US
    private val now = (golden.getDouble("now") * 1000).toLong()
    private val birth = (golden.getDouble("birth") * 1000).toLong()
    private val child = Child(id = "child", name = golden.getString("childName"), birthDate = birth)

    private val events: List<LogEvent> = golden.getJSONArray("events").objects().map { row ->
        val start = (row.getDouble("start") * 1000).toLong()
        LogEvent(
            id = row.getString("id"),
            childId = child.id,
            kind = EventKind.fromRaw(row.getString("kind"))!!,
            startedAt = start,
            endedAt = if (row.has("end")) (row.getDouble("end") * 1000).toLong() else null,
            side = row.optString("side").ifEmpty { null },
            amount = row.getDouble("amount"),
            stoolColor = row.optString("stool").ifEmpty { null },
            note = row.optString("note").ifEmpty { null },
            createdAt = start,
        )
    }.sortedByDescending { it.start } // newest first, as EventStore hands them out on both platforms

    /** ICU writes a narrow no-break space before AM/PM; the JDK's CLDR may not. */
    private fun norm(s: String) = s.replace(' ', ' ')

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }
    private fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }
    private fun JSONObject.millisOrNull(key: String): Long? = if (isNull(key)) null else (getDouble(key) * 1000).toLong()
    private fun JSONObject.stringOrNull(key: String): String? = if (isNull(key)) null else getString(key)

    @Test
    fun eventsLoaded() {
        assertEquals(46, events.size)
    }

    @Test
    fun nowSummaryLinesMatchIOS() {
        val cases = golden.getJSONArray("summaries").objects()
        assertEquals(24, cases.size)
        for (case in cases) {
            val words = DiaperWords.fromRaw(case.getString("words"))
            val hidden = case.getJSONArray("hidden").strings().map { EventKind.fromRaw(it)!! }.toSet()
            val tracked = TrackedKinds(hidden)
            val window = TotalsWindow.fromStored(case.getInt("window"))
            val label = "${case.getString("words")}/${case.getString("tracked")}/${case.getInt("window")}"
            val s = NowSummary.make(child, events, now, zone, window, tracked, words)
            val e = case.getJSONObject("summary")
            assertEquals(label, e.getString("feedLine"), s.feedLine(now))
            assertEquals(label, e.getString("diaperLine"), s.diaperLine(now))
            assertEquals(label, e.getString("awakeLine"), s.awakeLine(now))
            assertEquals(label, e.stringOrNull("sleepLine"), s.sleepLine(now))
            assertEquals(label, e.getString("todayLine"), s.todayLine)
            assertEquals(label, e.stringOrNull("nextSideLine"), s.nextSideLine)
            assertEquals(label, e.getString("leadLine"), s.leadLine(now))
            assertEquals(label, e.getJSONArray("supportingLines").strings(), s.supportingLines(now))
            assertEquals(label, e.getString("leadElapsed"), s.leadElapsed(now))
            assertEquals(label, e.getInt("dayOfLife"), s.dayOfLife)
            assertEquals(label, e.getInt("todayFeeds"), s.todayFeeds)
            assertEquals(label, e.getInt("todayWet"), s.todayWet)
            assertEquals(label, e.getInt("todayDirty"), s.todayDirty)
            assertEquals(label, e.millisOrNull("lastFeedAt"), s.lastFeedAt)
            assertEquals(label, e.millisOrNull("runningSleepStart"), s.runningSleepStart)
            assertEquals(label, e.millisOrNull("lastWokeAt"), s.lastWokeAt)
            assertEquals(label, e.getJSONArray("recentTitles").strings(), s.recent.take(8).map { it.title(words) })
            assertEquals(label, case.getString("headline"), tracked.headline)
            assertEquals(label, norm(case.getString("windowTitle")), norm(window.title(locale)))

            val visible = events.filter { tracked.contains(it.kind) }
            val totals = WindowTotals.make(visible, window, now, zone)
            val t = case.getJSONObject("totals")
            assertEquals(label, t.getInt("feeds"), totals.feeds)
            assertEquals(label, t.getInt("wet"), totals.wet)
            assertEquals(label, t.getInt("dirty"), totals.dirty)
            assertEquals(label, t.getDouble("sleepSeconds"), totals.sleepSeconds, 0.001)
            assertEquals(label, t.getInt("futureFrom"), totals.futureFrom)
            assertEquals(label, (t.getDouble("gridStart") * 1000).toLong(), totals.gridStart)
            assertEquals(label, t.getString("line"), totals.line(tracked, words))
            val hours = t.getJSONObject("hours")
            for (kind in WindowTotals.KINDS) {
                val expected = hours.getJSONArray(kind.raw)
                val actual = totals.hours.getValue(kind)
                for (i in 0 until WindowTotals.COLUMNS) assertEquals("$label ${kind.raw}[$i]", expected.getDouble(i), actual[i], 0.0001)
            }
        }
    }

    @Test
    fun dayTalliesMatchIOS() {
        for (row in golden.getJSONArray("tallies").objects()) {
            val day = java.time.LocalDate.of(2026, 10, row.getInt("day")).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
            val t = DayTally.make(events, day, now, zone)
            val label = "Oct ${row.getInt("day")}"
            assertEquals(label, row.getInt("feeds"), t.feeds)
            assertEquals(label, row.getInt("wet"), t.wet)
            assertEquals(label, row.getInt("dirty"), t.dirty)
            assertEquals(label, row.getDouble("sleepSeconds"), t.sleepSeconds, 0.001)
            assertEquals(label, row.getDouble("bottle"), t.bottleMillilitres, 0.001)
        }
    }

    @Test
    fun summaryReportsMatchIOS() {
        val cases = golden.getJSONArray("reports").objects()
        assertEquals(2, cases.size)
        for (case in cases) {
            val hidden = case.getJSONArray("hidden").strings().map { EventKind.fromRaw(it)!! }.toSet()
            val r = SummaryReport.make(
                child.displayName, birth, events,
                (case.getDouble("from") * 1000).toLong(), (case.getDouble("to") * 1000).toLong(),
                TrackedKinds(hidden), now, zone,
            )
            val e = case.getJSONObject("report")
            assertEquals((e.getDouble("start") * 1000).toLong(), r.start)
            assertEquals((e.getDouble("end") * 1000).toLong(), r.end)
            assertEquals(e.getString("rangeLabel"), r.rangeLabel(locale))
            assertEquals(e.getDouble("averageFeeds"), r.averageFeedsPerDay, 1e-9)
            assertEquals(e.getDouble("averageWet"), r.averageWetPerDay, 1e-9)
            assertEquals(e.getDouble("averageDirty"), r.averageDirtyPerDay, 1e-9)
            assertEquals(e.getDouble("averageSleep"), r.averageSleepSeconds, 1e-6)
            assertEquals(e.getDouble("longestSleep"), r.longestSleepSeconds, 1e-6)
            assertEquals(e.getDouble("longestGap"), r.longestFeedGapSeconds, 1e-6)
            assertEquals(e.getDouble("bottlePerDay"), r.averageBottleMillilitresPerDay, 1e-9)
            assertEquals(e.getDouble("bottlePerFeed"), r.averageBottleMillilitresPerFeed, 1e-9)
            assertEquals(norm(e.getString("averagesNote")), norm(r.averagesNote(locale)))
            assertEquals(e.stringOrNull("weightChange"), r.weightChangeDescription(imperial = true, locale = locale))
            assertEquals(e.stringOrNull("weightChangeMetric"), r.weightChangeGrams?.let { Format.gramsChange(it, imperial = false) })
            assertEquals(e.millisOrNull("lowestWetDay"), r.lowestDay { it.wet }?.date)
            val notes = e.getJSONArray("notes").objects()
            assertEquals(notes.map { it.getString("text") }, r.notes.map { it.second })
            val days = e.getJSONArray("days").objects()
            assertEquals(days.size, r.days.size)
            days.zip(r.days).forEach { (d, a) ->
                val label = Format.monthDay(a.date, zone, locale)
                assertEquals(label, (d.getDouble("date") * 1000).toLong(), a.date)
                assertEquals(label, if (d.isNull("dayOfLife")) null else d.getInt("dayOfLife"), a.dayOfLife)
                assertEquals(label, d.getInt("feeds"), a.feeds)
                assertEquals(label, d.getInt("wet"), a.wet)
                assertEquals(label, d.getInt("dirty"), a.dirty)
                assertEquals(label, d.getDouble("bottle"), a.bottleMillilitres, 1e-9)
                assertEquals(label, d.getDouble("sleep"), a.sleepSeconds, 1e-6)
                assertEquals(label, d.getDouble("longestSleep"), a.longestSleepSeconds, 1e-6)
                assertEquals(label, d.getDouble("gap"), a.longestFeedGapSeconds, 1e-6)
                assertEquals(label, d.getInt("bottleFeeds"), a.bottleFeeds)
                assertEquals(label, if (d.isNull("weight")) null else d.getDouble("weight"), a.weightGrams)
                assertEquals(label, d.getJSONArray("stools").strings(), a.stoolColors.map { it.raw })
                assertEquals(label, d.stringOrNull("partial")?.let(::norm), a.partial?.label(zone, locale)?.let(::norm))
            }
        }
    }

    @Test
    fun csvMatchesIOSExceptTheDateColumn() {
        val expected = golden.getString("csv").trimEnd('\n').split("\n")
        val actual = SummaryReport.csv(events, child.displayName, zone, locale).trimEnd('\n').split("\n")
        assertEquals(expected.size, actual.size)
        assertEquals(SummaryReport.CSV_HEADER, actual.first())
        // iOS formats the date column in UTC (an evening entry lands on the next
        // day); Android writes the local day. Every other column must match.
        fun withoutDate(line: String) = norm(line).split(",").let { it.take(1) + it.drop(2) }.joinToString(",")
        expected.zip(actual).forEach { (e, a) -> assertEquals(withoutDate(e), withoutDate(a)) }
        val evening = actual.first { it.contains("6:10") }
        assertTrue(evening, evening.startsWith("Elsa,2026-10-10,"))
    }

    @Test
    fun formatMatchesIOS() {
        val f = golden.getJSONObject("format")
        f.getJSONArray("compact").objects().forEach { assertEquals(it.getString("v"), Format.compactDuration(it.getDouble("s"))) }
        f.getJSONArray("duration").objects().forEach { assertEquals(it.getString("v"), Format.duration(it.getDouble("s"))) }
        f.getJSONArray("asleep").objects().forEach { assertEquals(it.getString("v"), Format.asleep(it.getDouble("s"))) }
        f.getJSONArray("ml").objects().forEach {
            assertEquals(it.getString("metric"), Format.millilitres(it.getDouble("v"), false))
            assertEquals(it.getString("imperial"), Format.millilitres(it.getDouble("v"), true))
        }
        f.getJSONArray("grams").objects().forEach {
            assertEquals(it.getString("metric"), Format.grams(it.getDouble("v"), false))
            assertEquals(it.getString("imperial"), Format.grams(it.getDouble("v"), true))
        }
        f.getJSONArray("gramsChange").objects().forEach {
            assertEquals(it.getString("metric"), Format.gramsChange(it.getDouble("v"), false))
            assertEquals(it.getString("imperial"), Format.gramsChange(it.getDouble("v"), true))
        }
    }

    @Test
    fun guidanceMatchesIOS() {
        for (row in golden.getJSONArray("guidance").objects()) {
            val r = Guidance.range(row.getInt("day"))
            assertEquals(row.getInt("outDay"), r.day)
            assertEquals(row.getInt("wet"), r.wetMin)
            assertEquals(row.getInt("dirty"), r.dirtyMin)
            assertEquals(row.getString("stool"), r.stoolNote)
            assertEquals(row.getString("summary"), r.summary)
        }
        val text = golden.getJSONObject("guidanceText")
        assertEquals(text.getString("sourceLine"), Guidance.SOURCE_LINE)
        assertEquals(text.getString("referenceScope"), Guidance.REFERENCE_SCOPE)
        assertEquals(text.getString("disclaimer"), Guidance.DISCLAIMER)
        assertEquals(text.getJSONArray("callIf").strings(), Guidance.CALL_IF)
    }

    @Test
    fun stainGuideMatchesIOS() {
        val rules = golden.getJSONObject("stainRules")
        assertEquals(rules.getString("careLabel"), StainGuide.CARE_LABEL_RULE)
        assertEquals(rules.getString("never"), StainGuide.NEVER_RULE)
        golden.getJSONArray("supplies").objects().forEach {
            val supply = StainGuide.Supply.fromRaw(it.getString("id"))!!
            assertEquals(it.getString("label"), supply.label)
            assertEquals(it.getString("hint"), supply.hint)
        }
        val cases = golden.getJSONArray("stains").objects()
        assertEquals(25, cases.size)
        for (case in cases) {
            val stain = StainGuide.Stain.entries.first { it.raw == case.getString("stain") }
            val owned = case.getJSONArray("owned").strings().map { StainGuide.Supply.fromRaw(it)!! }.toSet()
            assertEquals(case.getString("label"), stain.label)
            assertEquals(case.getString("firstMove"), stain.firstMove)
            val steps = StainGuide.steps(stain, owned)
            val expected = case.getJSONArray("steps").objects()
            assertEquals(expected.map { it.getString("title") }, steps.map { it.title })
            assertEquals(expected.map { it.getString("detail") }, steps.map { it.detail })
            assertEquals(expected.map { it.stringOrNull("caution") }, steps.map { it.caution })
            assertEquals(expected.map { it.stringOrNull("supply") }, steps.map { it.supply?.raw })
            assertEquals(case.getJSONArray("missing").strings(), StainGuide.missing(stain, owned).map { it.raw })
        }
    }

    @Test
    fun remindersMatchIOS() {
        val summary = NowSummary.make(child, events, now, zone, TotalsWindow.MIDNIGHT, TrackedKinds.ALL)
        for (row in golden.getJSONArray("feedReminders").objects()) {
            val interval = FeedReminderInterval.fromMinutes(row.getInt("minutes"))
            assertEquals(row.getString("label"), interval.label)
            val p = ReminderPlan.feedReminder(summary, interval, now, zone, locale)
            assertEquals(row.millisOrNull("date"), p?.date)
            assertEquals(row.stringOrNull("title"), p?.title)
            assertEquals(row.stringOrNull("body")?.let(::norm), p?.body?.let(::norm))
        }
        val dayNine = java.time.LocalDateTime.of(2026, 10, 9, 9, 0).atZone(zone).toInstant().toEpochMilli()
        val typical = ReminderPlan.checkupReminders(birth, null, dayNine, zone)
        val expected = golden.getJSONArray("checkups").objects()
        assertEquals(3, expected.size)
        assertEquals(expected.map { it.getString("id") }, typical.map { it.id })
        assertEquals(expected.map { (it.getDouble("date") * 1000).toLong() }, typical.map { it.date })
        assertEquals(expected.map { it.getString("body") }, typical.map { it.body })
        val visit = java.time.LocalDateTime.of(2026, 10, 20, 10, 0).atZone(zone).toInstant().toEpochMilli()
        val entered = ReminderPlan.checkupReminders(birth, visit, now, zone)
        val enteredExpected = golden.getJSONArray("enteredCheckup").objects()
        assertEquals(enteredExpected.map { (it.getDouble("date") * 1000).toLong() }, entered.map { it.date })
        assertEquals(enteredExpected.map { it.getString("title") }, entered.map { it.title })
    }

    @Test
    fun trackedKindsHeadlinesMatchIOS() {
        val rows = golden.getJSONArray("headlines").objects()
        assertEquals(16, rows.size)
        for (row in rows) {
            val hidden = row.getJSONArray("hidden").strings().map { EventKind.fromRaw(it)!! }.toSet()
            val tracked = TrackedKinds(hidden)
            assertEquals(row.getString("headline"), tracked.headline)
            assertEquals(row.getJSONArray("buttons").strings(), tracked.buttons.map { it.raw })
        }
    }
}
