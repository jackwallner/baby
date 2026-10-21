package com.jackwallner.baby

import com.jackwallner.baby.model.Child
import com.jackwallner.baby.model.ConversionCopy
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedSide
import com.jackwallner.baby.model.FeedingStyle
import com.jackwallner.baby.model.FeedReminderInterval
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.model.LogOps
import com.jackwallner.baby.model.LogState
import com.jackwallner.baby.model.NowSummary
import com.jackwallner.baby.model.PlusFeature
import com.jackwallner.baby.model.TotalsWindow
import com.jackwallner.baby.model.TrackedKinds
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The iOS EventStore rules, ported to [LogOps], pinned the way iOS EventStoreTests pins them. */
class LogRulesTest {
    private val zone = ZoneId.of("America/Los_Angeles")
    private val child = Child(id = "a", name = "Elsa")
    private val base = LogState(listOf(child), emptyList(), child.id)
    private val t0 = 1_792_000_000_000L
    private val minute = 60_000L

    @Test
    fun aFeedTapLogsAnInstantFeedWithNoSide() {
        val (state, event) = LogOps.log(base, EventKind.FEED, t0, t0)!!
        assertEquals(1, state.events.size)
        assertEquals(t0, event.endedAt)
        assertTrue(event.feedSides.isEmpty())
        assertFalse(event.isRunning)
    }

    @Test
    fun aDiaperHasNoSideAndNoEnd() {
        val (_, event) = LogOps.log(base, EventKind.WET, t0, t0, side = FeedSide.LEFT)!!
        assertNull(event.side)
        assertNull(event.endedAt)
    }

    @Test
    fun aFeedDuringARunningFeedEndsIt() {
        val (running, timer) = LogOps.startTimed(base, EventKind.FEED, t0, t0)!!
        val (state, _) = LogOps.log(running, EventKind.FEED, t0 + 20 * minute, t0 + 20 * minute)!!
        assertEquals(t0 + 20 * minute, state.events.first { it.id == timer.id }.endedAt)
    }

    @Test
    fun aBackdatedFeedLeavesALaterTimerRunning() {
        val (running, timer) = LogOps.startTimed(base, EventKind.FEED, t0, t0)!!
        val (state, _) = LogOps.log(running, EventKind.FEED, t0 - 30 * minute, t0)!!
        assertTrue(state.events.first { it.id == timer.id }.isRunning)
    }

    @Test
    fun startingSleepTwiceNeverLeavesTwoOpenRows() {
        val (one, _) = LogOps.startTimed(base, EventKind.SLEEP, t0, t0)!!
        val (two, _) = LogOps.startTimed(one, EventKind.SLEEP, t0 + minute, t0 + minute)!!
        assertEquals(1, two.events.count { it.isRunning })
    }

    @Test
    fun wakeEndsEveryOpenSleepAndReturnsNullWhenNothingRuns() {
        val twoParents = base.copy(events = listOf(
            LogEvent(id = "s1", childId = "a", kind = EventKind.SLEEP, startedAt = t0),
            LogEvent(id = "s2", childId = "a", kind = EventKind.SLEEP, startedAt = t0 + 5 * minute),
        ))
        val woke = LogOps.stopRunning(twoParents, EventKind.SLEEP, t0 + 60 * minute, t0 + 60 * minute)!!
        assertTrue(woke.events.none { it.isRunning })
        assertNull(LogOps.stopRunning(woke, EventKind.SLEEP, t0 + 61 * minute, t0 + 61 * minute))
    }

    @Test
    fun aStopBeforeTheStartNeverMakesANegativeSleep() {
        val (running, _) = LogOps.startTimed(base, EventKind.SLEEP, t0, t0)!!
        val woke = LogOps.stopRunning(running, EventKind.SLEEP, t0 - 10 * minute, t0)!!
        assertEquals(0.0, woke.events.single().duration!!, 0.0)
    }

    @Test
    fun loggingOnlyTouchesTheActiveBaby() {
        val other = Child(id = "b")
        val state = base.copy(children = listOf(child, other), events = listOf(LogEvent(id = "x", childId = "b", kind = EventKind.SLEEP, startedAt = t0)))
        val woke = LogOps.stopRunning(state, EventKind.SLEEP, t0 + minute, t0 + minute)
        assertNull("baby b's sleep is not this baby's", woke)
    }

    @Test
    fun sidesKeepTapOrderAndOneSideStaysABareValue() {
        assertEquals("right,left", FeedSide.encode(listOf(FeedSide.RIGHT, FeedSide.LEFT, FeedSide.RIGHT)))
        assertEquals("left", FeedSide.encode(listOf(FeedSide.LEFT)))
        assertEquals(listOf(FeedSide.RIGHT, FeedSide.LEFT), FeedSide.decode("right,left,bogus"))
        assertNull(FeedSide.encode(emptyList()))
    }

    @Test
    fun theNextSideSkipsABottleInBetween() {
        val events = listOf(
            LogEvent(childId = "a", kind = EventKind.FEED, startedAt = t0, endedAt = t0, side = "right,left"),
            LogEvent(childId = "a", kind = EventKind.FEED, startedAt = t0 + 60 * minute, endedAt = t0 + 60 * minute, side = "bottle"),
        )
        val summary = NowSummary.make(child, events, t0 + 90 * minute, zone, TotalsWindow.MIDNIGHT, TrackedKinds.ALL)
        assertEquals("Start on Right", summary.nextSideLine)
    }

    @Test
    fun atLeastOneButtonStaysOn() {
        assertEquals(TrackedKinds.ALL, TrackedKinds(TrackedKinds.BUTTONS.toSet()))
        assertEquals(setOf(EventKind.FEED), TrackedKinds(setOf(EventKind.FEED, EventKind.WEIGHT)).hidden)
    }

    @Test
    fun aHiddenKindLeavesTheSummaryButStaysInTheLog() {
        val (state, _) = LogOps.log(base, EventKind.WET, t0, t0)!!
        val summary = NowSummary.make(child, state.events, t0 + minute, zone, TotalsWindow.MIDNIGHT, TrackedKinds(setOf(EventKind.WET)))
        assertEquals(0, summary.todayWet)
        assertNull(summary.lastDiaperAt)
        assertEquals(1, state.events.size)
    }

    @Test
    fun theLogSurvivesAJsonRoundTrip() {
        val (one, _) = LogOps.log(base, EventKind.FEED, t0, t0)!!
        val (two, _) = LogOps.startTimed(one, EventKind.SLEEP, t0 + minute, t0 + minute)!!
        val edited = LogOps.upsert(two, two.events.first().copy(side = "left,bottle", amount = 60.0, note = "Fussy, \"a lot\""), t0 + 2 * minute)
        val restored = LogState.fromJson(edited.toJson())
        assertEquals(edited, restored)
        assertNotNull(restored.events.first { it.kind == EventKind.SLEEP && it.isRunning })
    }

    @Test
    fun anUnknownKindFromANewerBuildIsSkipped() {
        val json = base.toJson().replace("\"events\":[]", "\"events\":[{\"id\":\"z\",\"childId\":\"a\",\"kind\":\"bath\",\"startedAt\":1,\"createdAt\":1,\"updatedAt\":1}]")
        assertTrue(LogState.fromJson(json).events.isEmpty())
    }

    @Test
    fun removingABabySwitchesToAnother() {
        val other = Child(id = "b")
        val state = LogOps.removeChild(base.copy(children = listOf(child, other)), "a")
        assertEquals("b", state.activeChild?.id)
    }

    @Test
    fun theFeedingStyleOnlyPicksTheFirstReminderGap() {
        assertEquals(FeedReminderInterval.THREE_HOURS, FeedingStyle.BOTTLE.suggestedInterval)
        assertEquals(FeedReminderInterval.TWO_AND_A_HALF_HOURS, FeedingStyle.BREAST.suggestedInterval)
    }

    @Test
    fun purchaseCopyLeadsWithTheBilledAmountAndNeverPricesTheButton() {
        assertEquals("Continue with Baby+", ConversionCopy.CTA)
        assertEquals("$24.99 per year", ConversionCopy.billedAmount("$24.99 / year"))
        assertEquals("1-week free trial included · Cancel anytime", ConversionCopy.billedNote("1-Week free trial", true))
        assertEquals("Billed automatically · Cancel anytime", ConversionCopy.billedNote("1-week free trial", false))
        assertTrue(ConversionCopy.disclosure("1-week free trial", "$3.99 / month", true).startsWith("$3.99 / month after the 1-week free trial. Auto-renews"))
        assertTrue(ConversionCopy.disclosure(null, "$3.99 / month", false).contains("Google Play"))
    }

    @Test
    fun babyPlusIsReportingOnly() {
        assertEquals(listOf("Pediatrician summary", "Trends", "CSV export"), PlusFeature.entries.map { it.title })
    }
}
