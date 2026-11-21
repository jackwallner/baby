package com.jackwallner.baby

import com.jackwallner.baby.model.Child
import com.jackwallner.baby.model.DateHelpers
import com.jackwallner.baby.model.Format
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

/** A birth date is a calendar day: entered in one zone, it reads as the same day in every other. */
class BirthDateTest {
    private val zones = listOf(
        "Pacific/Honolulu", "America/Los_Angeles", "America/New_York", "UTC", "Europe/Paris", "Asia/Kolkata",
        "Asia/Tokyo", "Pacific/Auckland", "Pacific/Chatham", "Pacific/Kiritimati", "Pacific/Pago_Pago",
    ).map(ZoneId::of)
    private val born = LocalDate.of(2026, 10, 9)

    @Test
    fun birthDateKeepsItsCalendarDayInEveryZone() {
        val stored = DateHelpers.birthStamp(born)
        for (zone in zones) {
            assertEquals("read in $zone", born, DateHelpers.birthDay(stored, zone))
            assertEquals("shown in $zone", "Oct 9, 2026", Format.birthDate(stored, zone, Locale.US))
        }
    }

    @Test
    fun dayOfLifeCountsFromTheEnteredDayWhereverThePhoneIs() {
        val stored = DateHelpers.birthStamp(born)
        for (zone in zones) {
            val onBirthday = ZonedDateTime.of(2026, 10, 9, 12, 0, 0, 0, zone).toInstant().toEpochMilli()
            val nextDay = ZonedDateTime.of(2026, 10, 10, 0, 5, 0, 0, zone).toInstant().toEpochMilli()
            assertEquals("day 1 in $zone", 1, Child(birthDate = stored).dayOfLife(onBirthday, zone))
            assertEquals("day 2 in $zone", 2, Child(birthDate = stored).dayOfLife(nextDay, zone))
            assertEquals("day 3 date in $zone", LocalDate.of(2026, 10, 11),
                DateHelpers.localDate(DateHelpers.dateForDayOfLife(3, stored, zone), zone))
        }
    }

    @Test
    fun readingABirthDateWritesNothing() {
        // Settings shows and re-saves the stored value untouched: a day read back and stamped again is the same value.
        for (zone in zones) {
            val stored = DateHelpers.birthStamp(born)
            assertEquals(stored, DateHelpers.birthStamp(DateHelpers.birthDay(stored, zone)))
        }
    }

    @Test
    fun aBirthDateFromAnEarlierBuildStillReadsInTheZoneItWasEnteredIn() {
        // Earlier builds stored the local midnight of the day; it still reads as that day in the same zone.
        val tokyo = ZoneId.of("Asia/Tokyo")
        val legacy = DateHelpers.dayStartOf(born, tokyo)
        assertEquals(born, DateHelpers.birthDay(legacy, tokyo))
    }

    @Test
    fun birthStampsAtTheDayEdgesKeepTheirDay() {
        for (date in listOf(LocalDate.of(2026, 3, 8), LocalDate.of(2026, 11, 1), LocalDate.of(2026, 1, 1), LocalDate.of(2026, 12, 31))) {
            val stored = DateHelpers.birthStamp(date)
            for (zone in zones) assertEquals("$date in $zone", date, DateHelpers.birthDay(stored, zone))
        }
    }
}
