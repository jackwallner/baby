package com.jackwallner.baby

import com.jackwallner.baby.model.DateHelpers
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.ReminderPlan
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

/** The next checkup is a calendar day: picked in one zone, it and its evening note stay on that day in every other. */
class NextCheckupTest {
    private val visit = LocalDate.of(2026, 12, 3)
    private val la = ZoneId.of("America/Los_Angeles")
    private val readers = listOf("Asia/Tokyo", "Pacific/Auckland", "Europe/London", "Pacific/Honolulu", "America/Los_Angeles").map(ZoneId::of)
    private val now = ZonedDateTime.of(2026, 11, 21, 9, 0, 0, 0, la).toInstant().toEpochMilli()

    private fun at(day: LocalDate, hour: Int, zone: ZoneId) =
        day.atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()

    @Test
    fun dayPickedLateEveningInLosAngelesReadsTheSameEverywhere() {
        val stored = DateHelpers.birthStamp(visit)
        for (zone in readers) {
            assertEquals("read in $zone", visit, DateHelpers.birthDay(stored, zone))
            assertEquals("shown in $zone", "Dec 3, 2026", Format.birthDate(stored, zone, Locale.US))
        }
    }

    @Test
    fun eveningBeforeStaysOnThePickedDayInEveryZone() {
        val stored = DateHelpers.birthStamp(visit)
        for (zone in readers) {
            val plan = ReminderPlan.checkupReminders(null, stored, now, zone).single()
            assertEquals("evening in $zone", at(visit.minusDays(1), 19, zone), plan.date)
        }
    }

    @Test
    fun legacyValueReadsAsBefore() {
        // An earlier build stored 10:00 local in the zone it was entered, here Los Angeles.
        val legacy = at(visit, 10, la)
        assertEquals(visit, DateHelpers.birthDay(legacy, la))
        assertEquals("Dec 3, 2026", Format.birthDate(legacy, la, Locale.US))
        val plan = ReminderPlan.checkupReminders(null, legacy, now, la).single()
        assertEquals(at(visit.minusDays(1), 19, la), plan.date)
    }

    @Test
    fun aVisitDayThatHasPassedPlansNothingFromTheEnteredDate() {
        val past = DateHelpers.birthStamp(LocalDate.of(2026, 11, 20))
        assertEquals(emptyList<ReminderPlan.Planned>(), ReminderPlan.checkupReminders(null, past, now, la))
    }
}
