package com.jackwallner.baby.model

import java.time.ZoneId
import java.util.Locale

/**
 * The first-weeks reference. The diaper figures are NHS Healthier Together's
 * breastfeeding guide; fever advice is the AAP's. Educational context, never
 * an assessment of the baby's counts. Pinned to iOS by golden.json.
 */
object Guidance {
    data class DayRange(val day: Int, val wetMin: Int, val dirtyMin: Int, val stoolNote: String, val feedsMin: Int, val feedsMax: Int) {
        val wetText: String get() = "$wetMin+ wet"
        val dirtyText: String get() = "$dirtyMin+ dirty"
        val feedsText: String get() = "$feedsMin to $feedsMax feeds"
        val summary: String get() = "$wetText · $dirtyText · $feedsText"
    }

    const val SOURCE_LINE = "Diaper reference: NHS Healthier Together breastfeeding guidance. Fever and newborn care: American Academy of Pediatrics. Your pediatrician's advice comes first."
    const val REFERENCE_SCOPE = "A breastfeeding reference for the first two weeks, not a target for every baby. Formula or mixed feeding can have different patterns. Follow your pediatrician's feeding plan. Counts include only what you log."
    const val DIAPER_SOURCE = "https://www.swlondon-healthiertogether.nhs.uk/new-baby/keeping-your-child-safe-2-1/breastfeeding-your-baby"
    const val FEVER_SOURCE = "https://www.healthychildren.org/English/health-issues/conditions/fever/Pages/Fever-and-Your-Baby.aspx"
    const val FEEDING_SOURCE = "https://www.healthychildren.org/English/ages-stages/baby/feeding-nutrition/Pages/how-often-and-how-much-should-your-baby-eat.aspx"
    const val DISCLAIMER = "Baby Tracker is a log, not medical advice. It does not diagnose, treat or assess your baby. Typical ranges are general guidance; call your pediatrician with any concern."
    const val TALLY_DAYS = 14

    fun range(dayOfLife: Int): DayRange {
        val d = maxOf(1, dayOfLife)
        return when (d) {
            1 -> DayRange(1, 1, 1, "black and tarry (meconium)", 8, 12)
            2 -> DayRange(2, 2, 1, "black to dark green", 8, 12)
            3 -> DayRange(3, 3, 2, "brown, green or yellow", 8, 12)
            4 -> DayRange(4, 4, 2, "brown, green or yellow", 8, 12)
            5 -> DayRange(5, 5, 2, "yellow and loose", 8, 12)
            else -> DayRange(d, 6, 2, "yellow and loose", 8, 12)
        }
    }

    val CALL_IF = listOf(
        "Your baby has fewer wet diapers than usual, feeds poorly, or you are worried about feeding or weight gain.",
        "Your newborn has not passed the first dark stool within 48 hours of birth.",
        "Your baby is difficult to wake for feeds: seek medical advice right away.",
        "Pink or brick-red diaper staining continues, or you notice blood in the urine or stool.",
        "At 3 months or younger, a rectal temperature of 100.4°F (38°C) or higher needs an immediate call, even if your baby seems well.",
    )
}

/** Laundry help for baby stains, using only what the parent has at home. */
object StainGuide {
    enum class Supply(val raw: String, val label: String, val hint: String) {
        DISH_SOAP("dishSoap", "Dish soap", "The blue kind by the sink."),
        DETERGENT("detergent", "Laundry detergent", "Most have enzymes, which is what breaks milk and poop down."),
        OXYGEN_BLEACH("oxygenBleach", "Oxygen bleach (OxiClean)", "Colour-safe powder. Not chlorine bleach."),
        HYDROGEN_PEROXIDE("hydrogenPeroxide", "Hydrogen peroxide 3%", "The brown bottle from the medicine cabinet."),
        WHITE_VINEGAR("whiteVinegar", "White vinegar", "For the sour-milk smell."),
        BAKING_SODA("bakingSoda", "Baking soda", "For smell, not for the stain.");

        companion object {
            fun fromRaw(raw: String): Supply? = entries.firstOrNull { it.raw == raw }
        }
    }

    enum class Stain(val raw: String, val label: String, val shortLabel: String, val firstMove: String) {
        BLOWOUT("blowout", "Blowout", "Blowout", "Get it off the skin first, then peel the clothes downward if you can, not over the head."),
        POOP("poop", "Poop", "Poop", "Lift the solids off with the edge of a wipe. Don't rub."),
        SPIT_UP("spitUp", "Spit-up", "Spit-up", "Blot, don't rub. Rubbing pushes it into the weave."),
        BREAST_MILK("breastMilk", "Breast milk", "Milk", "Rinse it now if you can. Dried milk is a different job."),
        FORMULA("formula", "Formula", "Formula", "Rinse it now if you can. Dried formula is a different job."),
    }

    /** At most one product per step. */
    data class Step(val supply: Supply?, val title: String, val detail: String, val caution: String?)

    const val CARE_LABEL_RULE = "Check the care label first, and never put two products on the fabric in the same step. Rinse in between."
    const val NEVER_RULE = "No chlorine bleach on baby clothes here, and never mix hydrogen peroxide or vinegar with anything else."

    private val rinse = Step(null, "Cold water, from the back", "Hold the fabric wrong side up and run cold water through the back of the stain so it goes out the way it came in. Never hot: heat cooks milk and poop into the fibres.", null)
    private val dishSoap = Step(Supply.DISH_SOAP, "A drop of dish soap", "Work one drop in with a fingertip, wait five minutes, rinse cold. It is built to lift the fat in milk, which is half of what a baby stain is.", null)
    private val detergent = Step(Supply.DETERGENT, "Rub in a little detergent", "Enzymes in ordinary laundry detergent break down protein. Rub a little straight into the damp stain and leave it fifteen minutes before washing.", null)
    private val oxygenSoak = Step(Supply.OXYGEN_BLEACH, "Soak in oxygen bleach", "Dissolve the powder in warm water to the dose on the tub, submerge the garment, and leave it one to eight hours. This is the one that gets old stains out.", "Colour-safe, but check the label for wool and silk.")
    private val sun = Step(null, "Lay it in the sun, still damp", "Sunlight fades the yellow of breastfed poop and milk better than anything in the cupboard, and it is free. A few hours, damp, stain side up.", null)
    private val peroxide = Step(Supply.HYDROGEN_PEROXIDE, "Dab hydrogen peroxide", "Dab it on, wait ten minutes, rinse cold. Rinse off any earlier product before this one.", "Whites and colourfast fabrics only. Test a hidden seam first.")
    private val vinegarSmell = Step(Supply.WHITE_VINEGAR, "Soak for the sour smell", "One part white vinegar to four parts cool water, thirty minutes, then rinse. This is for the smell that survives the wash, not for the mark.", "On its own, in clean water. Never alongside peroxide or bleach.")
    private val bakingSodaSmell = Step(Supply.BAKING_SODA, "Baking soda paste for the smell", "A spoon of baking soda with a little water, spread on, thirty minutes, brush off. Again: smell, not stain.", null)
    private val washAndCheck = Step(null, "Wash, then look before it dries", "Wash as warm as the care label allows, then check the garment while it is still wet. A dryer sets whatever is left, and after that it is permanent.", null)

    fun steps(stain: Stain, owning: Set<Supply>): List<Step> {
        val ordered = when (stain) {
            Stain.BLOWOUT, Stain.POOP -> listOf(rinse, dishSoap, detergent, oxygenSoak, sun, peroxide, washAndCheck)
            Stain.SPIT_UP -> listOf(rinse, dishSoap, detergent, bakingSodaSmell, oxygenSoak, washAndCheck)
            Stain.BREAST_MILK -> listOf(rinse, detergent, dishSoap, oxygenSoak, sun, washAndCheck)
            Stain.FORMULA -> listOf(rinse, dishSoap, detergent, oxygenSoak, vinegarSmell, washAndCheck)
        }
        return ordered.filter { it.supply == null || it.supply in owning }
    }

    fun missing(stain: Stain, owning: Set<Supply>): List<Supply> {
        val all = when (stain) {
            Stain.BLOWOUT, Stain.POOP -> listOf(dishSoap, detergent, oxygenSoak, peroxide)
            Stain.SPIT_UP -> listOf(dishSoap, detergent, bakingSodaSmell, oxygenSoak)
            Stain.BREAST_MILK -> listOf(detergent, dishSoap, oxygenSoak)
            Stain.FORMULA -> listOf(dishSoap, detergent, oxygenSoak, vinegarSmell)
        }
        return all.mapNotNull { it.supply }.filter { it !in owning }
    }
}

/** The gap a parent picked between the start of one feed and a nudge for the next. */
enum class FeedReminderInterval(val minutes: Int, val label: String, val shortLabel: String) {
    OFF(0, "Off", "Off"),
    TWO_HOURS(120, "2 hours", "2h"),
    TWO_AND_A_HALF_HOURS(150, "2½ hours", "2½h"),
    THREE_HOURS(180, "3 hours", "3h"),
    THREE_AND_A_HALF_HOURS(210, "3½ hours", "3½h"),
    FOUR_HOURS(240, "4 hours", "4h");

    companion object {
        val CHOICES = entries.filter { it != OFF }
        fun fromMinutes(minutes: Int): FeedReminderInterval = entries.firstOrNull { it.minutes == minutes } ?: OFF
    }
}

/** How the baby is fed, asked once at setup. It only picks which reminder gap is offered first. */
enum class FeedingStyle(val raw: String, val label: String) {
    BREAST("breast", "Breast"),
    BOTTLE("bottle", "Formula"),
    BOTH("both", "Both"),
    PUMPED("pumped", "Pumped milk"),
    EXPECTING("expecting", "Not born yet");

    val suggestedInterval: FeedReminderInterval
        get() = if (this == BOTTLE) FeedReminderInterval.THREE_HOURS else FeedReminderInterval.TWO_AND_A_HALF_HOURS

    companion object {
        fun fromRaw(raw: String?): FeedingStyle? = entries.firstOrNull { it.raw == raw }
    }
}

/** This phone's local notifications, planned as pure data. Port of iOS `Reminders`. */
object ReminderPlan {
    const val FEED_ID = "baby.feed"
    const val CHECKUP_PREFIX = "baby.checkup."
    const val CHECKUP_ROUTE = "checkup"
    const val CHECKUP_EVENING_HOUR = 19
    val TYPICAL_CHECKUP_DAYS = listOf(4, 14, 30)

    data class Planned(val id: String, val date: Long, val title: String, val body: String, val route: String?)

    fun feedReminder(summary: NowSummary, interval: FeedReminderInterval, now: Long, zone: ZoneId, locale: Locale = Locale.getDefault()): Planned? {
        if (interval == FeedReminderInterval.OFF || summary.isFeeding) return null
        val last = summary.lastFeedAt ?: return null
        val due = last + interval.minutes * 60_000L
        if (due <= now + 30_000) return null
        val started = "Last feed started at ${Format.time(last, zone, locale)}."
        val body = summary.nextBreastSide?.let { "$started Start on ${it.label}." } ?: started
        return Planned(FEED_ID, due, "${interval.label} since ${summary.childName}'s last feed", body, null)
    }

    fun checkupReminders(birthDate: Long?, nextCheckup: Long?, now: Long, zone: ZoneId): List<Planned> {
        if (nextCheckup != null && nextCheckup > now) {
            val evening = eveningBefore(nextCheckup, zone)
            if (evening <= now) return emptyList()
            return listOf(Planned(CHECKUP_PREFIX + "entered", evening, "Checkup tomorrow",
                "Feeds, diapers, sleep and weight since the last visit are in Baby Tracker.", CHECKUP_ROUTE))
        }
        birthDate ?: return emptyList()
        return TYPICAL_CHECKUP_DAYS.mapNotNull { day ->
            val evening = eveningBefore(DateHelpers.dateForDayOfLife(day, birthDate, zone), zone)
            if (evening <= now) null
            else Planned(CHECKUP_PREFIX + "day$day", evening, "Checkup coming up?",
                "Newborn visits come often in the first month. Your log has the feeds, diapers and sleep to bring.", CHECKUP_ROUTE)
        }
    }

    private fun eveningBefore(date: Long, zone: ZoneId): Long =
        DateHelpers.localDate(date, zone).minusDays(1).atTime(CHECKUP_EVENING_HOUR, 0).atZone(zone).toInstant().toEpochMilli()
}

/** Baby+ is reporting to share with a doctor, nothing else. */
enum class PlusFeature(val title: String, val detail: String, val pitchLine: String) {
    PEDIATRICIAN_SUMMARY(
        "Pediatrician summary",
        "A one-page PDF since the last visit: feeds and the longest gap between them, wet and dirty counts, sleep, weights. Hand it over or share it in the exam room.",
        "One page for every visit, to share or print",
    ),
    TRENDS("Trends", "Feeds per day, longest sleep stretch and diaper counts over the weeks.", "Feeds, diapers and sleep week over week"),
    EXPORT("CSV export", "Every entry as a spreadsheet, for your records or a specialist.", "Every entry as a spreadsheet"),
}

/** Purchase copy. The button carries no pricing words; the billed amount leads. */
object ConversionCopy {
    const val CTA = "Continue with Baby+"
    const val HEDGE = "Baby Tracker is a log, not medical advice."
    private const val RENEW_CLAUSE = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Google Play › Payments & subscriptions › Subscriptions."
    const val PENDING = "Waiting on Google Play to confirm this purchase. Baby+ turns on by itself as soon as it goes through, so there is nothing to tap again."

    /** "$24.99 / year" -> "$24.99 per year". */
    fun billedAmount(priceLabel: String): String = priceLabel.replace(" / ", " per ")

    fun billedNote(trialLabel: String?, eligibleForTrial: Boolean): String =
        if (eligibleForTrial && !trialLabel.isNullOrEmpty()) "${trialLabel.lowercase()} included · Cancel anytime"
        else "Billed automatically · Cancel anytime"

    fun disclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Boolean): String =
        if (eligibleForTrial && !trialLabel.isNullOrEmpty()) "$priceLabel after the ${trialLabel.lowercase()}. $RENEW_CLAUSE"
        else "$priceLabel. $RENEW_CLAUSE"

    fun cancelled(eligibleForTrial: Boolean): String =
        if (eligibleForTrial) "Trial wasn't started. Tap again to continue." else "Purchase wasn't completed. Tap again to continue."

    fun failed(eligibleForTrial: Boolean): String =
        if (eligibleForTrial) "Couldn't start your trial. Please try again." else "Couldn't complete the purchase. Please try again."
}
