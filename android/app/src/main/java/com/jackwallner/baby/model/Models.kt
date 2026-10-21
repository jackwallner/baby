package com.jackwallner.baby.model

import java.time.ZoneId
import java.util.UUID

/** What a tap logs. The raw values are stored and exported, so they never change. */
enum class EventKind(val raw: String) {
    FEED("feed"),
    WET("wet"),
    DIRTY("dirty"),
    SLEEP("sleep"),
    /** Reporting only. Logged from the editor, never from the four buttons. */
    WEIGHT("weight");

    val isDiaper: Boolean get() = this == WET || this == DIRTY

    /** Kinds that can be running (started, not yet ended). */
    val canRun: Boolean get() = this == FEED || this == SLEEP

    /** The on-screen name, in the parent's chosen diaper words. */
    fun label(words: DiaperWords): String = when (this) {
        FEED -> "Feed"
        WET -> if (words == DiaperWords.PEE_POOP) "Pee" else "Wet"
        DIRTY -> if (words == DiaperWords.PEE_POOP) "Poop" else "Dirty"
        SLEEP -> "Sleep"
        WEIGHT -> "Weight"
    }

    companion object {
        fun fromRaw(raw: String?): EventKind? = entries.firstOrNull { it.raw == raw }
    }
}

enum class FeedSide(val raw: String, val label: String, val shortLabel: String) {
    LEFT("left", "Left", "L"),
    RIGHT("right", "Right", "R"),
    BOTTLE("bottle", "Bottle", "Bottle");

    /** The other breast after a breastfeed, the bottle again after a bottle. */
    val next: FeedSide get() = when (this) {
        LEFT -> RIGHT
        RIGHT -> LEFT
        BOTTLE -> BOTTLE
    }

    companion object {
        fun fromRaw(raw: String?): FeedSide? = entries.firstOrNull { it.raw == raw }

        /** "Left", "Left + Right", "Right + Bottle", in the order chosen. */
        fun label(sides: List<FeedSide>): String? =
            if (sides.isEmpty()) null else sides.joinToString(" + ") { it.label }

        fun shortLabel(sides: List<FeedSide>): String? =
            if (sides.isEmpty()) null else sides.joinToString("+") { it.shortLabel }

        /** Comma-separated in tap order; one side stays its bare raw value, as on iOS. */
        fun encode(sides: List<FeedSide>): String? {
            val seen = sides.distinct()
            return if (seen.isEmpty()) null else seen.joinToString(",") { it.raw }
        }

        fun decode(raw: String?): List<FeedSide> =
            (raw ?: "").split(",").mapNotNull(::fromRaw).distinct()
    }
}

enum class StoolColor(val raw: String, val label: String) {
    BLACK("black", "Black"),
    GREEN("green", "Green"),
    YELLOW("yellow", "Yellow"),
    BROWN("brown", "Brown"),
    OTHER("other", "Other");

    companion object {
        fun fromRaw(raw: String?): StoolColor? = entries.firstOrNull { it.raw == raw }
    }
}

/** Pee and Poop by default; Wet and Dirty for parents who prefer them. */
enum class DiaperWords(val raw: String, val label: String) {
    PEE_POOP("peePoop", "Pee and Poop"),
    WET_DIRTY("wetDirty", "Wet and Dirty");

    companion object {
        fun fromRaw(raw: String?): DiaperWords = entries.firstOrNull { it.raw == raw } ?: PEE_POOP
    }
}

/**
 * Which of the four buttons this family uses. A kind that is turned off
 * leaves Now, History and the reports; its entries stay in the log.
 */
class TrackedKinds(hidden: Set<EventKind>) {
    val hidden: Set<EventKind> = hidden.intersect(BUTTONS.toSet()).let { if (it.size >= BUTTONS.size) emptySet() else it }

    fun contains(kind: EventKind): Boolean = kind !in hidden

    val buttons: List<EventKind> get() = BUTTONS.filter(::contains)

    val tracksDiapers: Boolean get() = contains(EventKind.WET) || contains(EventKind.DIRTY)

    /** "Feeds, diapers and sleep". */
    val headline: String
        get() {
            val parts = mutableListOf<String>()
            if (contains(EventKind.FEED)) parts += "feeds"
            if (tracksDiapers) parts += "diapers"
            if (contains(EventKind.SLEEP)) parts += "sleep"
            val joined = if (parts.size > 1) parts.dropLast(1).joinToString(", ") + " and " + parts.last() else parts.joinToString("")
            return joined.replaceFirstChar { it.uppercase() }
        }

    override fun equals(other: Any?): Boolean = other is TrackedKinds && other.hidden == hidden
    override fun hashCode(): Int = hidden.hashCode()

    companion object {
        val BUTTONS = listOf(EventKind.FEED, EventKind.WET, EventKind.DIRTY, EventKind.SLEEP)
        val ALL = TrackedKinds(emptySet())
    }
}

data class Child(
    val id: String = UUID.randomUUID().toString(),
    val name: String? = null,
    /** Epoch millis. */
    val birthDate: Long? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val lastVisitAt: Long? = null,
    /** Last change to the name or birth date, for last-writer-wins when logging together. */
    val updatedAt: Long = createdAt,
) {
    /** Never empty: Now and the PDF need a word. */
    val displayName: String get() = name?.trim().takeUnless { it.isNullOrEmpty() } ?: "Baby"

    fun dayOfLife(on: Long, zone: ZoneId): Int? = birthDate?.let { DateHelpers.dayOfLife(it, on, zone) }
}

data class LogEvent(
    val id: String = UUID.randomUUID().toString(),
    val childId: String,
    val kind: EventKind,
    /** Epoch millis. */
    val startedAt: Long,
    val endedAt: Long? = null,
    val side: String? = null,
    /** Millilitres for a bottle, grams for a weight. Zero means "not entered". */
    val amount: Double = 0.0,
    val stoolColor: String? = null,
    val note: String? = null,
    val createdAt: Long = startedAt,
    val updatedAt: Long = createdAt,
) {
    val start: Long get() = startedAt

    val feedSides: List<FeedSide> get() = FeedSide.decode(side)

    val stool: StoolColor? get() = StoolColor.fromRaw(stoolColor)

    /** Started and not ended. An instant feed is stored with endedAt == startedAt. */
    val isRunning: Boolean get() = kind.canRun && endedAt == null

    /** Seconds, or null with no end. */
    val duration: Double? get() = endedAt?.let { maxOf(0.0, (it - startedAt) / 1000.0) }

    fun withSides(sides: List<FeedSide>): LogEvent = copy(side = FeedSide.encode(sides))

    /** "Left", "Bottle 60 ml", "Yellow", "1h 05m". */
    fun detailText(imperial: Boolean): String? = when (kind) {
        EventKind.FEED -> {
            val parts = mutableListOf<String>()
            FeedSide.label(feedSides)?.let(parts::add)
            if (FeedSide.BOTTLE in feedSides && amount > 0) parts += Format.millilitres(amount, imperial)
            duration?.let { if (it >= 60) parts += Format.compactDuration(it) }
            if (parts.isEmpty()) null else parts.joinToString(" · ")
        }
        EventKind.DIRTY -> stool?.label
        EventKind.SLEEP -> if (isRunning) "Asleep" else duration?.let(Format::duration)
        EventKind.WET -> null
        EventKind.WEIGHT -> if (amount > 0) Format.grams(amount, imperial) else null
    }
}
