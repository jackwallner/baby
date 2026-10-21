package com.jackwallner.baby.model

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sign

object DateHelpers {
    fun zoned(millis: Long, zone: ZoneId): ZonedDateTime = Instant.ofEpochMilli(millis).atZone(zone)

    fun localDate(millis: Long, zone: ZoneId): LocalDate = zoned(millis, zone).toLocalDate()

    fun startOfDay(millis: Long, zone: ZoneId): Long = localDate(millis, zone).atStartOfDay(zone).toInstant().toEpochMilli()

    fun addDays(dayStart: Long, days: Long, zone: ZoneId): Long =
        zoned(dayStart, zone).plusDays(days).toInstant().toEpochMilli()

    fun dayStartOf(date: LocalDate, zone: ZoneId): Long = date.atStartOfDay(zone).toInstant().toEpochMilli()

    /** Day 1 is the calendar day of birth; null before birth. */
    fun dayOfLife(birthDate: Long, on: Long, zone: ZoneId): Int? {
        val days = ChronoUnit.DAYS.between(localDate(birthDate, zone), localDate(on, zone))
        return if (days >= 0) days.toInt() + 1 else null
    }

    /** The calendar day for a given day of life, 1-based. */
    fun dateForDayOfLife(day: Int, birthDate: Long, zone: ZoneId): Long =
        dayStartOf(localDate(birthDate, zone).plusDays((day - 1).toLong()), zone)

    fun daysBetween(from: Long, to: Long, zone: ZoneId): Long =
        ChronoUnit.DAYS.between(localDate(from, zone), localDate(to, zone))
}

/** Every string that shows a time, a duration or an amount goes through here. */
object Format {
    /** Swift's `rounded()`: to nearest, halves away from zero. */
    fun roundAway(value: Double): Double = sign(value) * floor(abs(value) + 0.5)

    /** "just now", "12m ago", "2h 14m ago". */
    fun ago(date: Long, now: Long): String {
        val seconds = maxOf(0.0, (now - date) / 1000.0)
        if (seconds < 60) return "just now"
        return "${compactDuration(seconds)} ago"
    }

    /** "12m", "2h 14m", "1d 3h". Minutes only under an hour, no seconds. */
    fun compactDuration(seconds: Double): String {
        val minutes = (seconds / 60).toInt()
        val hours = minutes / 60
        val days = hours / 24
        if (days >= 1) {
            val remHours = hours % 24
            return if (remHours > 0) "${days}d ${remHours}h" else "${days}d"
        }
        if (hours >= 1) {
            val remMinutes = minutes % 60
            return if (remMinutes > 0) "${hours}h ${remMinutes}m" else "${hours}h"
        }
        return "${maxOf(minutes, 0)}m"
    }

    fun duration(seconds: Double): String = if (seconds < 60) "under a minute" else compactDuration(seconds)

    fun asleep(seconds: Double): String = if (seconds < 60) "Asleep just now" else "Asleep ${compactDuration(seconds)}"

    fun time(millis: Long, zone: ZoneId, locale: Locale = Locale.getDefault()): String =
        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).format(DateHelpers.zoned(millis, zone))

    /** "Oct 10". */
    fun monthDay(millis: Long, zone: ZoneId, locale: Locale = Locale.getDefault()): String =
        DateTimeFormatter.ofPattern("MMM d", locale).format(DateHelpers.zoned(millis, zone))

    /** "Oct 10, 2026". */
    fun monthDayYear(millis: Long, zone: ZoneId, locale: Locale = Locale.getDefault()): String =
        DateTimeFormatter.ofPattern("MMM d, yyyy", locale).format(DateHelpers.zoned(millis, zone))

    fun dayTitle(day: Long, now: Long, zone: ZoneId, locale: Locale = Locale.getDefault()): String {
        val date = DateHelpers.localDate(day, zone)
        val today = DateHelpers.localDate(now, zone)
        return when {
            date == today -> "Today"
            date == today.minusDays(1) -> "Yesterday"
            date.year == today.year -> DateTimeFormatter.ofPattern("EEE, MMM d", locale).format(date)
            else -> DateTimeFormatter.ofPattern("MMM d, yyyy", locale).format(date)
        }
    }

    /** "6 AM", or "06" style hours where the locale uses a 24-hour clock. */
    fun hourLabel(hour: Int, locale: Locale = Locale.getDefault()): String {
        val pattern = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale)
            .format(java.time.LocalTime.of(13, 0))
        return if (pattern.contains("1")) {
            DateTimeFormatter.ofPattern("h a", locale).format(java.time.LocalTime.of(hour, 0))
        } else {
            DateTimeFormatter.ofPattern("HH:mm", locale).format(java.time.LocalTime.of(hour, 0))
        }
    }

    /** Ounces and pounds in the US, metric elsewhere, as on iOS. */
    fun usesImperial(locale: Locale = Locale.getDefault()): Boolean =
        locale.country in setOf("US", "LR", "MM")

    const val MILLILITRES_PER_OUNCE = 29.5735
    const val GRAMS_PER_OUNCE = 28.3495

    /** "7.5", "11": up to one fraction digit, as ICU rounds (half even). */
    private fun upToOneDecimal(value: Double): String =
        BigDecimal(value).setScale(1, RoundingMode.HALF_EVEN).stripTrailingZeros().let {
            if (it.scale() < 0) it.setScale(0) else it
        }.toPlainString()

    fun millilitres(value: Double, imperial: Boolean): String {
        if (!imperial) return "${roundAway(value).toInt()} ml"
        val ounces = roundAway(value / MILLILITRES_PER_OUNCE * 2) / 2
        return "${upToOneDecimal(ounces)} oz"
    }

    fun grams(value: Double, imperial: Boolean): String {
        if (!imperial) return String.format(Locale.US, "%.2f kg", value / 1000)
        val totalOunces = roundAway(value / GRAMS_PER_OUNCE * 2) / 2
        val pounds = (totalOunces / 16).toInt()
        val ounces = totalOunces - pounds * 16.0
        return "$pounds lb ${upToOneDecimal(ounces)} oz"
    }

    /** A signed weight change, in the same units as [grams]. */
    fun gramsChange(value: Double, imperial: Boolean): String {
        val sign = if (value > 0) "+" else "−"
        if (!imperial) return "$sign${roundAway(abs(value)).toInt()} g"
        val ounces = roundAway(abs(value) / GRAMS_PER_OUNCE * 2) / 2
        return "$sign${upToOneDecimal(ounces)} oz"
    }

    fun count(n: Int, singular: String, plural: String? = null): String =
        if (n == 1) "$n $singular" else "$n ${plural ?: singular + "s"}"

    fun oneDecimal(value: Double): String = BigDecimal(value).setScale(1, RoundingMode.HALF_EVEN).toPlainString()
}
