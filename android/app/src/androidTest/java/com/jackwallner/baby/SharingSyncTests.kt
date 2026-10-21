package com.jackwallner.baby

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jackwallner.baby.SharingEmulator.Phone
import com.jackwallner.baby.SharingEmulator.eventually
import com.jackwallner.baby.data.SharingException
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedSide
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Two phones against the Firestore and Auth emulators, with the real
 * security rules: start, invite, join, log from both sides, delete, edit,
 * offline catch-up, a stale offline edit losing, remove and leave.
 */
@RunWith(AndroidJUnit4::class)
class SharingSyncTests {
    @Before
    fun emulator() {
        SharingEmulator.require()
    }

    private fun test(block: suspend () -> Unit) = runBlocking(Dispatchers.Main) { block() }

    /** Alice starts a log with Elsa and two entries; Bea joins with the invite. */
    private suspend fun aliceAndBea(): Pair<Phone, Phone> {
        val alice = Phone("Alice")
        alice.events.createChild("Elsa", null)
        alice.events.log(EventKind.WET)
        alice.events.log(EventKind.FEED)
        alice.sharing.start(alice.signIn)
        val code = alice.sharing.invite()
        val bea = Phone("Bea")
        bea.sharing.join(code, bea.signIn)
        return alice to bea
    }

    @Test
    fun aJoinerGetsTheWholeLogAndEitherPhoneCanLog() = test {
        val (alice, bea) = aliceAndBea()
        assertTrue(bea.sharing.isOn)
        assertFalse(bea.sharing.isOwner)
        assertEquals("Elsa", bea.events.child?.name)
        assertEquals(2, bea.events.events.size)

        bea.events.log(EventKind.DIRTY)
        eventually("Alice sees Bea's poop") { alice.events.events.any { it.kind == EventKind.DIRTY } }
        alice.events.startTimed(EventKind.SLEEP)
        eventually("Bea sees Alice's sleep running") { bea.events.runningSleep != null }
        eventually("both names on both phones") {
            alice.sharing.members.map { it.name }.toSet() == setOf("Alice", "Bea") && bea.sharing.members.size == 2
        }
        assertTrue(alice.sharing.isOwner)
    }

    @Test
    fun deletesAndEditsReachThePartner() = test {
        val (alice, bea) = aliceAndBea()
        val wet = alice.events.events.first { it.kind == EventKind.WET }
        alice.events.delete(wet)
        eventually("Bea's copy of the pee is gone") { bea.events.events.none { it.id == wet.id } }

        val feed = bea.events.events.first { it.kind == EventKind.FEED }
        bea.events.setSides(feed.id, listOf(FeedSide.RIGHT, FeedSide.LEFT))
        eventually("Alice sees Right + Left") { alice.events.events.first { it.id == feed.id }.side == "right,left" }

        bea.events.updateChild(bea.events.child!!, "Elsa Rose", null)
        eventually("Alice sees the new name") { alice.events.child?.name == "Elsa Rose" }
    }

    @Test
    fun undoTakesBackOnlyThisPhonesTap() = test {
        val (alice, bea) = aliceAndBea()
        alice.events.log(EventKind.WET)
        bea.events.log(EventKind.DIRTY)
        eventually("Alice has Bea's poop") { alice.events.events.any { it.kind == EventKind.DIRTY } }
        assertTrue(alice.events.undoLast())
        eventually("Bea loses Alice's second pee and keeps her poop") {
            bea.events.events.count { it.kind == EventKind.WET } == 1 && bea.events.events.any { it.kind == EventKind.DIRTY }
        }
        assertTrue(alice.events.events.any { it.kind == EventKind.DIRTY })
    }

    @Test
    fun anOfflinePhoneCatchesUpWhenItReconnects() = test {
        val (alice, bea) = aliceAndBea()
        bea.sharing.setNetwork(false)
        bea.events.log(EventKind.WET)
        bea.events.log(EventKind.WET)
        alice.events.log(EventKind.DIRTY)
        // Offline, Bea's taps still land on her own phone straight away.
        assertEquals(3, bea.events.events.count { it.kind == EventKind.WET })
        bea.sharing.setNetwork(true)
        eventually("Alice gets both pees") { alice.events.events.count { it.kind == EventKind.WET } == 3 }
        eventually("Bea gets the poop") { bea.events.events.any { it.kind == EventKind.DIRTY } }
    }

    @Test
    fun aStaleOfflineEditLosesToANewerOne() = test {
        val (alice, bea) = aliceAndBea()
        val feed = alice.events.events.first { it.kind == EventKind.FEED }
        bea.sharing.setNetwork(false)
        bea.events.setSides(feed.id, listOf(FeedSide.BOTTLE))
        delay(20)
        alice.events.setSides(feed.id, listOf(FeedSide.RIGHT))
        delay(1_000)
        bea.sharing.setNetwork(true)
        eventually("Bea ends up with Alice's newer Right") { bea.events.events.first { it.id == feed.id }.side == "right" }
        delay(1_000)
        assertEquals("right", alice.events.events.first { it.id == feed.id }.side)
    }

    @Test
    fun aMadeUpCodeIsRefusedWithAReason() = test {
        val bea = Phone("Bea")
        try {
            bea.sharing.join("ZZZZ2345", bea.signIn)
            fail("joined with a made-up code")
        } catch (e: SharingException) {
            assertEquals("That code doesn't match a shared log. Check it, or ask for a new one.", e.message)
        }
        assertFalse(bea.sharing.isOn)
    }

    @Test
    fun theOwnerRemovesSomeoneAndTheirPhoneKeepsItsCopy() = test {
        val (alice, bea) = aliceAndBea()
        eventually("Alice sees Bea") { alice.sharing.members.size == 2 }
        val code = alice.sharing.inviteCode
        alice.sharing.remove(alice.sharing.members.first { it.name == "Bea" })
        eventually("Bea is told") { !bea.sharing.isOn }
        assertNotNull(bea.sharing.notice)
        assertEquals(2, bea.events.events.size)
        // The withdrawn invite no longer works.
        val carl = Phone("Carl")
        try {
            carl.sharing.join(code!!, carl.signIn)
            fail("joined with a withdrawn invite")
        } catch (e: SharingException) {
            assertFalse(carl.sharing.isOn)
        }
        // A tap on Bea's phone now stays on Bea's phone.
        bea.events.log(EventKind.WET)
        delay(1_500)
        assertEquals(2, alice.events.events.size)
    }

    @Test
    fun leavingKeepsTheLogAndDeletesTheSignIn() = test {
        val (alice, bea) = aliceAndBea()
        bea.events.log(EventKind.DIRTY)
        eventually("Alice has it") { alice.events.events.size == 3 }
        bea.sharing.leave(bea.signIn)
        assertFalse(bea.sharing.isOn)
        assertFalse(bea.sharing.hasLeftoverAccount)
        assertEquals(3, bea.events.events.size)
        eventually("Alice sees Bea leave") { alice.sharing.members.size == 1 }
        // The last person out deletes the shared copy; Alice's phone keeps hers.
        alice.sharing.leave(alice.signIn)
        assertFalse(alice.sharing.isOn)
        assertEquals(3, alice.events.events.size)
    }
}
