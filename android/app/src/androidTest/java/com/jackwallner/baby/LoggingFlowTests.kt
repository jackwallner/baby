package com.jackwallner.baby

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The first-run path, one-tap logging, Undo, sides, sleep, turning a button
 * off, and the free / Baby+ boundary. Each test starts from a clean install
 * (orchestrator with clearPackageData).
 */
@RunWith(AndroidJUnit4::class)
class LoggingFlowTests {
    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    private val graph: AppGraph
        get() = (InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as BabyApplication).graph

    private fun onboard(name: String = "Elsa") {
        rule.onNodeWithTag("onboarding.name").performTextInput(name)
        rule.onNodeWithTag("onboarding.start").performScrollTo().performClick()
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("log.feed")).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test
    fun onboardingIsOneScreenWithNoPurchase() {
        rule.onNodeWithText("Hello, little one.").assertIsDisplayed()
        rule.onNodeWithText("How is the baby fed?").assertExists()
        assertTrue(rule.onAllNodes(hasText("Continue with Baby+")).fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("onboarding.feeding.bottle").performScrollTo().performClick()
        onboard()
        rule.onNodeWithTag("babyName").assertTextContains("Elsa")
        rule.onNodeWithTag("leadTime").assertTextContains("A fresh start")
        assertEquals("Elsa", graph.events.child?.name)
    }

    @Test
    fun aDiaperTapLogsAndUndoTakesItBack() {
        onboard()
        rule.onNodeWithTag("log.wet").performClick()
        rule.onNodeWithTag("undoToast").assertTextContains("Pee logged", substring = true)
        rule.onNodeWithTag("diaperLine").assertTextContains("Last diaper just now · Pee")
        assertEquals(1, graph.events.events.size)
        rule.onNodeWithTag("undo").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("diaperLine").assertTextContains("No diaper logged yet")
        assertEquals(0, graph.events.events.size)
    }

    @Test
    fun aFeedTapOpensOptionalSidesAndTheReminderOffer() {
        onboard()
        rule.onNodeWithTag("log.feed").performClick()
        rule.onNodeWithTag("leadTime").assertTextContains("just now")
        rule.onNodeWithTag("feedSide.left").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("leadDetail").assertTextContains("Left breast", substring = true)
        rule.onNodeWithTag("leadDetail").assertTextContains("Start on Right", substring = true)
        // The one-time reminder offer arrives six seconds after the feed.
        rule.waitUntil(10_000) { rule.onAllNodes(hasTestTag("offer.decline")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("offer.decline").performClick()
        assertTrue(graph.settings.hasOfferedFeedReminder)
    }

    @Test
    fun sleepThenWake() {
        onboard()
        rule.onNodeWithTag("log.sleep").performClick()
        rule.onNodeWithTag("log.sleep").assertTextContains("Wake", substring = true)
        assertTrue(graph.events.runningSleep != null)
        rule.onNodeWithTag("log.sleep").performClick()
        rule.onNodeWithTag("log.sleep").assertTextContains("Sleep", substring = true)
        assertTrue(graph.events.runningSleep == null)
    }

    @Test
    fun theLogClockBackdatesATap() {
        onboard()
        rule.onNodeWithTag("clock.earlier").performClick()
        rule.onNodeWithTag("clock.earlier").performClick()
        rule.onNodeWithTag("log.dirty").performClick()
        val logged = graph.events.events.single()
        val minutesAgo = (System.currentTimeMillis() - logged.start) / 60_000
        assertTrue("logged $minutesAgo minutes ago", minutesAgo in 9..11)
        rule.onNodeWithTag("clock.now").performClick()
        rule.onNodeWithTag("clock.label").assertTextContains("Now")
    }

    @Test
    fun turningAButtonOffRemovesItFromLog() {
        onboard()
        rule.onNodeWithTag("tab.settings").performClick()
        rule.onNodeWithTag("settings.button.sleep").performScrollTo().performClick()
        rule.onNodeWithTag("tab.log").performClick()
        rule.waitForIdle()
        assertTrue(rule.onAllNodes(hasTestTag("log.sleep")).fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("log.feed").assertExists()
    }

    @Test
    fun backfillingAWeightFromTheEditor() {
        onboard()
        rule.onNodeWithTag("olderEntry").performClick()
        rule.onNodeWithTag("olderEntry.weight").performClick()
        rule.onNodeWithTag("editor.amount").performTextInput("120")
        rule.onNodeWithTag("editor.save").performScrollTo().performClick()
        rule.waitForIdle()
        val weight = graph.events.state.events.single()
        assertEquals("weight", weight.kind.raw)
        assertTrue(weight.amount > 0)
    }

    @Test
    fun freeUserSeesThePaywallWithEveryRequiredElement() {
        onboard()
        rule.onNodeWithTag("tab.upgrade").assertTextContains("Upgrade", substring = true).performClick()
        rule.onNodeWithText("Reports for the pediatrician").assertIsDisplayed()
        rule.onNodeWithText("EXAMPLE, NOT YOUR BABY'S DATA").assertExists()
        rule.onNodeWithTag("paywall.disclosure").performScrollTo().assertExists()
        rule.onNodeWithTag("paywall.restore").performScrollTo().assertExists()
        rule.onNodeWithTag("paywall.terms").performScrollTo().assertExists()
        rule.onNodeWithTag("paywall.privacy").performScrollTo().assertExists()
        assertTrue(rule.onAllNodes(hasTestTag("reports.pdf")).fetchSemanticsNodes().isEmpty())
        // History stays free; only its trend chart is locked.
        rule.onNodeWithTag("tab.history").performClick()
        rule.onNodeWithTag("history.tile.today").assertExists()
        rule.onNodeWithTag("history.chart.unlock").assertExists()
    }

    @Test
    fun guidesAreFreeOnAFreshInstall() {
        onboard()
        rule.onNodeWithTag("tab.settings").performClick()
        rule.onNodeWithTag("settings.firstWeeks").performScrollTo().performClick()
        rule.onNodeWithTag("callCard").performScrollTo().assertExists()
        rule.onNodeWithTag("back").performClick()
        rule.onNodeWithTag("settings.stain").performScrollTo().performClick()
        rule.onNodeWithText("Cold water, from the back").performScrollTo().assertExists()
    }

    @Test
    fun babyPlusUnlocksReportsAndExport() {
        onboard()
        rule.runOnUiThread { graph.settings.updateDebugPlus(true) }
        rule.onNodeWithTag("log.wet").performClick()
        rule.onNodeWithTag("tab.upgrade").assertTextContains("Reports", substring = true).performClick()
        rule.onNodeWithTag("reports").assertExists()
        rule.onNodeWithTag("reports.pdf").performScrollTo().assertExists()
        rule.onNodeWithTag("reports.csv").performScrollTo().assertExists()
        rule.onNodeWithTag("reports.note").performScrollTo().assertExists()
    }
}
