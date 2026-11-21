package com.jackwallner.baby

import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.model.SummaryReport
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/** The CSV time column is a fixed 24 hour HH:mm in the date column's zone, whatever the phone's locale. */
class CsvTimeTest {
    private val saved = Locale.getDefault()
    private val zone = ZoneId.of("America/Los_Angeles")

    @Before fun pinLocale() = Locale.setDefault(Locale.US)

    @After fun restoreLocale() = Locale.setDefault(saved)

    private fun at(hour: Int, minute: Int): Long =
        ZonedDateTime.of(2026, 10, 10, hour, minute, 0, 0, zone).toInstant().toEpochMilli()

    private fun columns(millis: Long, locale: Locale): List<String> {
        Locale.setDefault(locale)
        val event = LogEvent(childId = "c", kind = EventKind.WET, startedAt = millis)
        return SummaryReport.csv(listOf(event), "Elsa", zone).trimEnd('\n').split("\n")[1].split(",")
    }

    @Test
    fun timeIsTwentyFourHourInEveryLocale() {
        for (locale in listOf(Locale.US, Locale.UK, Locale.GERMANY, Locale.JAPAN, Locale.forLanguageTag("ar-EG"), Locale.forLanguageTag("th-TH-u-nu-thai"))) {
            assertEquals("5:05 AM in $locale", "05:05", columns(at(5, 5), locale)[2])
            assertEquals("6:10 PM in $locale", "18:10", columns(at(18, 10), locale)[2])
            assertEquals("midnight in $locale", "00:00", columns(at(0, 0), locale)[2])
        }
    }

    @Test
    fun timeAndDateAreInTheSameZone() {
        val row = columns(at(23, 45), Locale.US)
        assertEquals("2026-10-10", row[1])
        assertEquals("23:45", row[2])
    }
}
