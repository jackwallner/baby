package com.jackwallner.baby

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jackwallner.baby.SharingEmulator.Phone
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.InviteCode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Log together as a person meets it: hidden without a Firebase project, the
 * Settings rows, starting and the invite code, joining from onboarding, an
 * opened invite link, and leaving.
 */
@RunWith(AndroidJUnit4::class)
class SharingUiTests {
    @get:Rule
    val rule = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null

    private val graph: AppGraph
        get() = (InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as BabyApplication).graph

    @After
    fun close() {
        scenario?.close()
    }

    private fun launch(intent: Intent? = null) {
        val start = intent ?: Intent(SharingEmulator.context, MainActivity::class.java)
        scenario = ActivityScenario.launch(start.setClass(SharingEmulator.context, MainActivity::class.java))
    }

    /** This app's own Firebase app on the emulators, as the debug launch extra does. */
    private fun useEmulator(name: String = "Sam") {
        InstrumentationRegistry.getInstrumentation().runOnMainSync { graph.sharing.useEmulator(SharingEmulator.require(), name) }
    }

    private fun onboard(name: String = "Elsa") {
        rule.onNodeWithTag("onboarding.name").performTextInput(name)
        rule.onNodeWithTag("onboarding.start").performScrollTo().performClick()
        waitFor("log.feed")
    }

    private fun waitFor(tag: String, timeoutMs: Long = 20_000) {
        rule.waitUntil(timeoutMs) { rule.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun openSettings() {
        rule.onNodeWithTag("tab.settings").performClick()
        waitFor("settings")
    }

    @Test
    fun withoutAFirebaseProjectSharingIsHidden() {
        launch()
        assertFalse(graph.sharing.isAvailable)
        assertTrue(rule.onAllNodes(hasTestTag("onboarding.path.join")).fetchSemanticsNodes().isEmpty())
        onboard()
        openSettings()
        assertTrue(rule.onAllNodes(hasText("Log together")).fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodes(hasTestTag("settings.partner.share")).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun startingShowsAnInviteCodeAndLeavingKeepsTheLog() {
        useEmulator()
        launch()
        onboard()
        rule.onNodeWithTag("log.wet").performClick()
        openSettings()
        rule.onNodeWithTag("settings.partner.share").performScrollTo().performClick()
        rule.onNodeWithText("Log together").assertIsDisplayed()
        rule.onNodeWithTag("sharing.access").assertExists()
        rule.onNodeWithTag("sharing.start").performScrollTo().performClick()
        waitFor("sharing.code")
        val code = graph.sharing.inviteCode!!
        rule.onNodeWithTag("sharing.code").assertTextContains(InviteCode.display(code))
        rule.onNodeWithText("No one has joined yet. Once they enter the code, their name appears here.").assertExists()
        // The member list arrives from the server just after the code.
        rule.waitUntil(20_000) { rule.onAllNodes(hasText("Sam (you)")).fetchSemanticsNodes().isNotEmpty() }
        assertTrue(graph.sharing.isOn)
        assertTrue(graph.sharing.isOwner)

        rule.onNodeWithTag("back").performClick()
        rule.onNodeWithTag("settings.partner.with").performScrollTo().assertTextContains("No one yet", substring = true)
        rule.onNodeWithTag("settings.partner.share").performClick()
        // Scrolled only to the viewport's edge, the last row sits under the tab capsule: click it directly.
        rule.onNodeWithTag("sharing.leave").performScrollTo().performSemanticsAction(SemanticsActions.OnClick)
        rule.onNodeWithText("You're the only one in it, so the shared copy is deleted too.", substring = true).assertExists()
        rule.onNodeWithTag("sharing.leaveConfirm").performClick()
        // Leaving finishes by deleting the sign-in; the page is back to its start when that is done.
        rule.waitUntil(20_000) { rule.onAllNodes(hasText("Continue with Google")).fetchSemanticsNodes().isNotEmpty() }
        assertFalse(graph.sharing.isOn)
        assertFalse(graph.sharing.hasLeftoverAccount)
        assertEquals(1, graph.events.events.size)
    }

    @Test
    fun aPartnerJoinsFromOnboardingAndLandsOnTheSharedBaby() {
        val code = runBlocking(Dispatchers.Main) {
            val alice = Phone("Alice")
            alice.events.createChild("Nora", null)
            alice.events.log(EventKind.FEED)
            alice.sharing.start(alice.signIn)
            alice.sharing.invite()
        }
        useEmulator("Bea")
        launch()
        rule.onNodeWithTag("onboarding.path.join").performClick()
        rule.onNodeWithTag("join.submit").assertIsNotEnabled()
        rule.onNodeWithTag("join.code").performTextInput(code.lowercase())
        rule.onNodeWithTag("join.submit").assertIsEnabled().performClick()
        waitFor("log.feed")
        rule.onNodeWithTag("babyName").assertTextContains("Nora")
        assertEquals(1, graph.events.events.size)
        assertTrue(graph.settings.hasCompletedSetup)
        openSettings()
        rule.waitUntil(20_000) { graph.sharing.members.size == 2 }
        rule.onNodeWithTag("settings.partner.with").performScrollTo().assertTextContains("Alice", substring = true)
    }

    @Test
    fun aWrongCodeSaysWhy() {
        useEmulator("Bea")
        launch()
        rule.onNodeWithTag("onboarding.path.join").performClick()
        rule.onNodeWithTag("join.code").performTextInput("ZZZZ-2345")
        rule.onNodeWithTag("join.submit").performClick()
        waitFor("sharing.error")
        rule.onNodeWithTag("sharing.error").assertTextContains("That code doesn't match a shared log", substring = true)
        rule.onNodeWithText("Hello, little one.").assertExists()
    }

    @Test
    fun anOpenedInviteLinkFillsInTheCode() {
        useEmulator("Bea")
        launch(Intent(Intent.ACTION_VIEW, Uri.parse("https://jackwallner.github.io/baby/join.html#WXYZ6789")))
        waitFor("join.code")
        rule.onNodeWithTag("join.code").assertTextContains("WXYZ-6789")
        rule.onNodeWithTag("join.submit").assertIsEnabled()
    }

    @Test
    fun anInviteLinkAfterSetupOpensJoinInSettings() {
        useEmulator("Bea")
        launch()
        onboard()
        scenario!!.onActivity { it.onNewIntent(Intent(Intent.ACTION_VIEW, Uri.parse("babytracker://join/WXYZ6789"))) }
        waitFor("join")
        rule.onNodeWithTag("join.code").assertTextContains("WXYZ-6789")
        rule.onNodeWithText("The babies already on this phone join the shared log too, with everything logged for them.").assertExists()
    }
}
