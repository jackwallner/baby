package com.jackwallner.baby

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Play reviewer unlock. Pass the throwaway code whose SHA-256 is in
 * local.properties with `-Pandroid.testInstrumentationRunnerArguments.reviewCode=...`;
 * without it the test reports as skipped.
 */
@RunWith(AndroidJUnit4::class)
class ReviewerUnlockTest {
    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    private val graph: AppGraph
        get() = (InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as BabyApplication).graph

    @Test
    fun longPressOnVersionRejectsAWrongCodeAndUnlocksBabyPlusWithTheRightOne() {
        val code = InstrumentationRegistry.getArguments().getString("reviewCode")
        assumeTrue("Pass the throwaway reviewer code as the reviewCode instrumentation argument", !code.isNullOrBlank())
        rule.onNodeWithTag("onboarding.start").performScrollTo().performClick()
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("log.feed")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("log.wet").performClick()
        assertFalse(graph.store.isPlus)

        rule.onNodeWithTag("tab.settings").performClick()
        rule.onNodeWithTag("settings.version").performScrollTo().performTouchInput { longClick() }

        rule.onNodeWithTag("settings.reviewerCode").performTextInput("wrong")
        rule.onNodeWithTag("settings.reviewerUnlock").performClick()
        rule.onNodeWithText("That code isn't valid.").assertIsDisplayed()
        assertFalse(graph.store.isPlus)

        rule.onNodeWithTag("settings.reviewerCode").performTextClearance()
        rule.onNodeWithTag("settings.reviewerCode").performTextInput(code!!)
        rule.onNodeWithTag("settings.reviewerUnlock").performClick()
        rule.waitForIdle()
        assertTrue(graph.store.isPlus)
        assertTrue(rule.onAllNodes(hasTestTag("settings.reviewerCode")).fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("tab.upgrade").assertTextContains("Reports", substring = true).performClick()
        rule.onNodeWithTag("reports.pdf").performScrollTo().assertExists()
        rule.onNodeWithTag("reports.csv").performScrollTo().assertExists()
    }
}
