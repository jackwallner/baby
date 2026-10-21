package com.jackwallner.baby

import com.jackwallner.baby.data.AppSettings
import com.jackwallner.baby.data.EventStore
import com.jackwallner.baby.model.Child
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.InviteCode
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.model.LogState
import com.jackwallner.baby.model.RemoteChild
import com.jackwallner.baby.model.RemoteEntry
import com.jackwallner.baby.model.SyncDiff
import com.jackwallner.baby.model.SyncDocs
import com.jackwallner.baby.model.SyncMerge
import kotlin.random.Random
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Log together's pure rules: what a change sends, how rows merge, codes and document fields. */
class SyncTest {
    private val child = Child(id = "a", name = "Elsa", createdAt = 100, updatedAt = 100)
    private fun feed(id: String, at: Long, updated: Long = at, side: String? = "left") =
        LogEvent(id = id, childId = "a", kind = EventKind.FEED, startedAt = at, endedAt = at, side = side, createdAt = at, updatedAt = updated)
    private val base = LogState(listOf(child), listOf(feed("f1", 1_000), feed("f2", 2_000)), "a")

    // MARK: What a local change sends

    @Test
    fun anUnchangedLogSendsNothing() {
        assertTrue(SyncDiff.changes(base, base, 5_000).isEmpty)
    }

    @Test
    fun aNewEntrySendsOneUpsert() {
        val after = base.copy(events = base.events + feed("f3", 3_000))
        val changes = SyncDiff.changes(base, after, 3_000)
        assertEquals(listOf("f3"), changes.entries.map { it.event.id })
        assertFalse(changes.entries.single().deleted)
        assertTrue(changes.children.isEmpty())
    }

    @Test
    fun aDeleteSendsATombstoneNewerThanTheEntry() {
        val after = base.copy(events = base.events.filterNot { it.id == "f1" })
        val tomb = SyncDiff.changes(base, after, 500).entries.single()
        assertTrue(tomb.deleted)
        assertEquals("f1", tomb.event.id)
        // The phone's clock is behind the entry's stamp: the tombstone still wins.
        assertEquals(1_001L, tomb.event.updatedAt)
    }

    @Test
    fun removingABabySendsItsTombstoneAndEveryEntrys() {
        val after = LogState(emptyList(), emptyList(), null)
        val changes = SyncDiff.changes(base, after, 9_000)
        assertEquals(listOf("a"), changes.children.filter { it.deleted }.map { it.child.id })
        assertEquals(setOf("f1", "f2"), changes.entries.filter { it.deleted }.map { it.event.id }.toSet())
    }

    @Test
    fun everythingSendsTheWholePhone() {
        val all = SyncDiff.everything(base)
        assertEquals(3, all.size)
    }

    // MARK: Stamping

    @Test
    fun anEditIsStampedNewerThanTheVersionItReplaced() {
        val edited = base.copy(events = base.events.map { if (it.id == "f2") it.copy(side = "right", updatedAt = 1_500) else it })
        val stamped = SyncDiff.stamp(base, edited, 1_200)
        val f2 = stamped.events.first { it.id == "f2" }
        assertEquals(2_001L, f2.updatedAt)
        // Untouched rows keep their stamp.
        assertEquals(1_000L, stamped.events.first { it.id == "f1" }.updatedAt)
    }

    @Test
    fun undoingADeleteStampsTheRestoredEntryNow() {
        val deleted = base.copy(events = base.events.filterNot { it.id == "f1" })
        val restored = SyncDiff.stamp(deleted, base, 10_000)
        assertEquals(10_000L, restored.events.first { it.id == "f1" }.updatedAt)
    }

    // MARK: Merging rows from the shared log

    @Test
    fun aNewerRemoteRowReplacesTheLocalOne() {
        val remote = RemoteEntry(feed("f1", 1_000, updated = 4_000, side = "right"))
        val merged = SyncMerge.merge(base, emptyList(), listOf(remote))
        assertEquals("right", merged.events.first { it.id == "f1" }.side)
    }

    @Test
    fun anOlderRemoteRowLosesToTheLocalOne() {
        val local = base.copy(events = listOf(feed("f1", 1_000, updated = 5_000, side = "right")))
        val merged = SyncMerge.merge(local, emptyList(), listOf(RemoteEntry(feed("f1", 1_000, updated = 4_000, side = "left"))))
        assertEquals("right", merged.events.single().side)
    }

    @Test
    fun aTombstoneRemovesTheEntryUnlessTheLocalOneIsNewer() {
        val gone = SyncMerge.merge(base, emptyList(), listOf(RemoteEntry(feed("f1", 1_000, updated = 3_000), deleted = true)))
        assertEquals(listOf("f2"), gone.events.map { it.id })
        val kept = SyncMerge.merge(base, emptyList(), listOf(RemoteEntry(feed("f2", 2_000, updated = 1_000), deleted = true)))
        assertEquals(2, kept.events.size)
    }

    @Test
    fun aPartnersEntryAndBabyArrive() {
        val sam = Child(id = "b", name = "Sam", createdAt = 50)
        val merged = SyncMerge.merge(base, listOf(RemoteChild(sam)), listOf(RemoteEntry(feed("p1", 2_500).copy(childId = "b"))))
        assertEquals(listOf("a", "b"), merged.children.map { it.id })
        assertEquals("a", merged.activeChildId)
        assertEquals(1, merged.eventsFor("b").size)
    }

    @Test
    fun mergingTheSameRowsTwiceChangesNothing() {
        val rows = listOf(RemoteEntry(feed("p1", 2_500)), RemoteEntry(feed("f1", 1_000, updated = 3_000), deleted = true))
        val once = SyncMerge.merge(base, emptyList(), rows)
        assertEquals(once, SyncMerge.merge(once, emptyList(), rows))
    }

    // MARK: The event store with logging together on

    private fun store(): EventStore {
        val settings = AppSettings(FakePrefs())
        var now = 1_000_000L
        return EventStore(null, settings, CoroutineScope(Dispatchers.Unconfined)) { now++ }
    }

    @Test
    fun eachTapIsHandedToTheSharedLog() {
        val events = store()
        val sent = mutableListOf<Pair<LogState, LogState>>()
        events.isShared = true
        events.onCommit = { before, after -> sent += before to after }
        events.createChild("Elsa", null)
        events.log(EventKind.WET)
        assertEquals(2, sent.size)
        val changes = SyncDiff.changes(sent[1].first, sent[1].second, 0)
        assertEquals(EventKind.WET, changes.entries.single().event.kind)
    }

    @Test
    fun aLocalOnlyPhoneSendsNothing() {
        val events = store()
        var sent = 0
        events.onCommit = { _, _ -> sent++ }
        events.createChild("Elsa", null)
        events.log(EventKind.WET)
        assertEquals(0, sent)
    }

    @Test
    fun remoteRowsAreNotSentBack() {
        val events = store()
        var sent = 0
        events.isShared = true
        events.createChild("Elsa", null)
        events.onCommit = { _, _ -> sent++ }
        val childId = events.child!!.id
        events.applyRemote(emptyList(), listOf(RemoteEntry(feed("p1", 999_000).copy(childId = childId))))
        assertEquals(0, sent)
        assertEquals(1, events.events.size)
    }

    @Test
    fun undoNeverTakesBackAPartnersEntry() {
        val events = store()
        events.isShared = true
        events.createChild("Elsa", null)
        val childId = events.child!!.id
        val sent = mutableListOf<Pair<LogState, LogState>>()
        events.onCommit = { before, after -> sent += before to after }
        events.log(EventKind.WET)
        // The partner's feed arrives inside the undo window.
        events.applyRemote(emptyList(), listOf(RemoteEntry(feed("p1", 999_000).copy(childId = childId))))
        assertTrue(events.undoLast())
        assertEquals(listOf("p1"), events.events.map { it.id })
        val undo = SyncDiff.changes(sent.last().first, sent.last().second, 0)
        assertEquals(listOf(EventKind.WET), undo.entries.map { it.event.kind })
        assertTrue(undo.entries.single().deleted)
    }

    @Test
    fun undoAfterADeleteSendsTheEntryBackNewerThanItsTombstone() {
        val events = store()
        events.isShared = true
        events.createChild("Elsa", null)
        val wet = events.log(EventKind.WET)!!
        events.dismissUndo()
        val sent = mutableListOf<Pair<LogState, LogState>>()
        events.onCommit = { before, after -> sent += before to after }
        events.delete(wet)
        val tomb = SyncDiff.changes(sent[0].first, sent[0].second, 0).entries.single()
        events.undoLast()
        val back = SyncDiff.changes(sent[1].first, sent[1].second, 0).entries.single()
        assertFalse(back.deleted)
        assertTrue(back.event.updatedAt > tomb.event.updatedAt || back.event.updatedAt >= wet.updatedAt + 1)
    }

    // MARK: Invite codes

    @Test
    fun codesUseOnlyUnambiguousCharacters() {
        val random = Random(7)
        repeat(200) {
            val code = InviteCode.generate(random)
            assertTrue(code, InviteCode.isValid(code))
            assertFalse(code.any { it in "01IO" })
        }
        assertEquals(32, InviteCode.ALPHABET.length)
        assertEquals(32, InviteCode.ALPHABET.toSet().size)
    }

    @Test
    fun codesAreReadFromWhateverWasPasted() {
        assertEquals("ABCD2345", InviteCode.parse("ABCD2345"))
        assertEquals("ABCD2345", InviteCode.parse(" abcd-2345 "))
        assertEquals("ABCD2345", InviteCode.parse("https://jackwallner.github.io/baby/join.html#ABCD2345"))
        assertEquals("ABCD2345", InviteCode.parse("babytracker://join/ABCD2345"))
        assertEquals(
            "WXYZ6789",
            InviteCode.parse("Join our baby log in Baby Tracker so we can both log feeds, diapers and sleep. Code WXYZ-6789, or open https://jackwallner.github.io/baby/join.html#WXYZ6789"),
        )
    }

    @Test
    fun aMistypedCodeIsNotACode() {
        assertNull(InviteCode.parse(""))
        assertNull(InviteCode.parse("ABCD-234"))
        assertNull(InviteCode.parse("ABCD-2340"))
        assertNull(InviteCode.parse("hello there"))
    }

    @Test
    fun codesDisplayAndLinkTheSameWay() {
        assertEquals("ABCD-2345", InviteCode.display("ABCD2345"))
        assertEquals("ABCD2345", InviteCode.parse(InviteCode.link("ABCD2345")))
    }

    // MARK: Document fields

    @Test
    fun anEntryRoundTripsThroughItsDocumentFields() {
        val event = LogEvent(id = "e1", childId = "a", kind = EventKind.FEED, startedAt = 1_000, endedAt = 2_000, side = "left,right",
            amount = 60.5, stoolColor = null, note = "sleepy", createdAt = 1_000, updatedAt = 3_000)
        val fields = SyncDocs.entryFields(RemoteEntry(event), "uid-1")
        assertEquals("feed", fields["kind"])
        assertEquals("uid-1", fields["updatedBy"])
        assertEquals(false, fields["deleted"])
        // The same field names as the local JSON, plus the sync fields.
        val json = org.json.JSONObject(LogState(listOf(child), listOf(event), "a").toJson()).getJSONArray("events").getJSONObject(0)
        assertEquals(json.keys().asSequence().toSet() + setOf("deleted", "updatedBy"), fields.keys)
        assertEquals(RemoteEntry(event), SyncDocs.entry(fields))
    }

    @Test
    fun firestoreNumberTypesAreAccepted() {
        // Firestore hands back integers as Long and an integral amount may come back as Long.
        val read = SyncDocs.entry(mapOf("id" to "e1", "childId" to "a", "kind" to "wet", "startedAt" to 5L, "amount" to 0L,
            "createdAt" to 5L, "updatedAt" to 6L, "deleted" to true, "syncedAt" to null))
        assertNotNull(read)
        assertTrue(read!!.deleted)
        assertEquals(0.0, read.event.amount, 0.0)
    }

    @Test
    fun aKindFromANewerAppIsSkipped() {
        assertNull(SyncDocs.entry(mapOf("id" to "e1", "childId" to "a", "kind" to "pump", "startedAt" to 5L, "createdAt" to 5L, "updatedAt" to 5L)))
    }

    @Test
    fun aBabyRoundTripsThroughItsDocumentFields() {
        val baby = Child(id = "a", name = null, birthDate = 77, createdAt = 10, lastVisitAt = null, updatedAt = 12)
        val fields = SyncDocs.childFields(RemoteChild(baby, deleted = true), "uid-1")
        assertEquals(RemoteChild(baby, deleted = true), SyncDocs.child(fields))
    }

    @Test
    fun aBabyFromAnOlderFileGetsItsUpdatedAtFromCreatedAt() {
        val old = """{"version":1,"activeChildId":"a","children":[{"id":"a","name":"Elsa","birthDate":null,"createdAt":42,"lastVisitAt":null}],"events":[]}"""
        assertEquals(42L, LogState.fromJson(old).children.single().updatedAt)
    }
}
