package com.jackwallner.baby

import com.jackwallner.baby.model.Child
import com.jackwallner.baby.model.DateHelpers
import com.jackwallner.baby.model.DiaperWords
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.model.NowSummary
import com.jackwallner.baby.model.TotalsWindow
import com.jackwallner.baby.model.TrackedKinds
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Clock edges: the 2 AM day start on the spring-forward morning. */
class ClockBoundaryTest {
    private val la = ZoneId.of("America/Los_Angeles")

    private fun at(zone: ZoneId, y: Int, m: Int, d: Int, h: Int, min: Int = 0): Long =
        ZonedDateTime.of(y, m, d, h, min, 0, 0, zone).toInstant().toEpochMilli()

    // Los Angeles springs forward at 2:00 AM on 2026-03-08, so 2:00 to 3:00 does not exist that morning.

    @Test
    fun twoAMWindowKeepsYesterdaysTwoAMOnSpringForwardMorning() {
        val now = at(la, 2026, 3, 8, 1, 30)
        val window = TotalsWindow.Day(2).interval(now, la)
        assertEquals(at(la, 2026, 3, 7, 2, 0), window.start)
        assertEquals(at(la, 2026, 3, 8, 3, 0), window.end)
        assertTrue(TotalsWindow.Day(2).holds(at(la, 2026, 3, 7, 2, 30), window))
    }

    @Test
    fun springForwardEntryAtTwoThirtyYesterdayIsCountedInTotals() {
        val child = Child(id = "c", name = "Elsa")
        val now = at(la, 2026, 3, 8, 1, 30)
        val entry = LogEvent(childId = child.id, kind = EventKind.FEED, startedAt = at(la, 2026, 3, 7, 2, 30), endedAt = at(la, 2026, 3, 7, 2, 30))
        val summary = NowSummary.make(child, listOf(entry), now, la, TotalsWindow.Day(2), TrackedKinds.ALL, DiaperWords.PEE_POOP)
        assertEquals(1, summary.todayFeeds)
    }

    @Test
    fun theWindowAfterSpringForwardStillStartsAtTwoOrThreeAMLocal() {
        // After the missing hour the day starts at the first 2 AM-or-later instant, as before.
        val now = at(la, 2026, 3, 8, 9, 0)
        assertEquals(at(la, 2026, 3, 8, 3, 0), TotalsWindow.Day(2).interval(now, la).start)
    }

    @Test
    fun anOrdinaryMorningIsUnchanged() {
        val now = at(la, 2026, 6, 10, 1, 30)
        val window = TotalsWindow.Day(2).interval(now, la)
        assertEquals(at(la, 2026, 6, 9, 2, 0), window.start)
        assertEquals(at(la, 2026, 6, 10, 2, 0), window.end)
    }

    // Day N on Now: the summary is built once, then read for hours.

    private fun summaryAt(birth: Long, now: Long, zone: ZoneId) =
        NowSummary.make(Child(id = "c", name = "Elsa", birthDate = birth), emptyList(), now, zone, TotalsWindow.MIDNIGHT, TrackedKinds.ALL, DiaperWords.PEE_POOP)

    @Test
    fun dayOfLifeStepsForwardAtMidnightWithoutANewSummary() {
        val birth = DateHelpers.birthStamp(LocalDate.of(2026, 10, 9))
        val built = at(la, 2026, 10, 13, 23, 50)
        val summary = summaryAt(birth, built, la)
        assertEquals(5, summary.dayOfLife(built, la))
        assertEquals(5, summary.dayOfLife(at(la, 2026, 10, 13, 23, 59), la))
        assertEquals(6, summary.dayOfLife(at(la, 2026, 10, 14, 0, 1), la))
    }

    @Test
    fun dayOfLifeStepsAtMidnightEvenWithASixAMTotalsDay() {
        val birth = DateHelpers.birthStamp(LocalDate.of(2026, 10, 9))
        val built = at(la, 2026, 10, 13, 23, 50)
        val summary = NowSummary.make(Child(id = "c", birthDate = birth), emptyList(), built, la, TotalsWindow.Day(6), TrackedKinds.ALL, DiaperWords.PEE_POOP)
        assertEquals(6, summary.dayOfLife(at(la, 2026, 10, 14, 0, 1), la))
    }

    @Test
    fun noBirthDateMeansNoDay() {
        assertEquals(null, NowSummary(birthDate = null).dayOfLife(at(la, 2026, 10, 13, 12, 0), la))
    }
}
