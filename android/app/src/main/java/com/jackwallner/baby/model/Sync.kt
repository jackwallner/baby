package com.jackwallner.baby.model

import kotlin.random.Random

/**
 * Log together on Android: the pure parts, so the JVM tests pin them.
 *
 * A shared log is one Firestore family holding every baby and entry on the
 * phones that joined it. Each row keeps the local JSON model's fields and id,
 * plus a `deleted` tombstone flag, and the newest `updatedAt` wins. The
 * schema is in `firebase/README.md`.
 */

/** A baby as stored in the shared log. */
data class RemoteChild(val child: Child, val deleted: Boolean = false)

/** An entry as stored in the shared log. */
data class RemoteEntry(val event: LogEvent, val deleted: Boolean = false)

/** What one local change sends to the shared log. */
data class SyncChanges(val children: List<RemoteChild> = emptyList(), val entries: List<RemoteEntry> = emptyList()) {
    val isEmpty: Boolean get() = children.isEmpty() && entries.isEmpty()
    val size: Int get() = children.size + entries.size
}

object SyncDiff {
    /**
     * Gives every row this change added, edited or brought back a stamp
     * newer than the version this phone last saw, so the shared log's
     * last-writer rule accepts it. Undo restores an old row; it still counts
     * as the newest write.
     */
    fun stamp(before: LogState, after: LogState, now: Long): LogState {
        val oldEvents = before.events.associateBy { it.id }
        val oldChildren = before.children.associateBy { it.id }
        return after.copy(
            events = after.events.map { e ->
                val old = oldEvents[e.id]
                if (old == e) e else e.copy(updatedAt = maxOf(now, e.updatedAt, (old?.updatedAt ?: 0) + 1))
            },
            children = after.children.map { c ->
                val old = oldChildren[c.id]
                if (old == c) c else c.copy(updatedAt = maxOf(now, c.updatedAt, (old?.updatedAt ?: 0) + 1))
            },
        )
    }

    /** Upserts for rows that differ, tombstones for rows that are gone. */
    fun changes(before: LogState, after: LogState, now: Long): SyncChanges {
        val oldEvents = before.events.associateBy { it.id }
        val newEvents = after.events.associateBy { it.id }
        val oldChildren = before.children.associateBy { it.id }
        val newChildren = after.children.associateBy { it.id }
        val entries = after.events.filter { oldEvents[it.id] != it }.map { RemoteEntry(it) } +
            before.events.filter { it.id !in newEvents }.map { RemoteEntry(it.copy(updatedAt = maxOf(now, it.updatedAt + 1)), deleted = true) }
        val children = after.children.filter { oldChildren[it.id] != it }.map { RemoteChild(it) } +
            before.children.filter { it.id !in newChildren }.map { RemoteChild(it.copy(updatedAt = maxOf(now, it.updatedAt + 1)), deleted = true) }
        return SyncChanges(children, entries)
    }

    /** Everything on this phone, for the first upload after starting or joining. */
    fun everything(state: LogState): SyncChanges =
        SyncChanges(state.children.map { RemoteChild(it) }, state.events.map { RemoteEntry(it) })
}

object SyncMerge {
    /**
     * Folds rows from the shared log into this phone's log. A row replaces
     * the local one unless the local one is newer; a tombstone removes it.
     * Which baby is active stays this phone's choice.
     */
    fun merge(state: LogState, children: List<RemoteChild>, entries: List<RemoteEntry>): LogState {
        if (children.isEmpty() && entries.isEmpty()) return state
        val kids = LinkedHashMap(state.children.associateBy { it.id })
        children.forEach { r ->
            val local = kids[r.child.id]
            if (local != null && local.updatedAt > r.child.updatedAt) return@forEach
            if (r.deleted) kids.remove(r.child.id) else kids[r.child.id] = r.child
        }
        val rows = LinkedHashMap(state.events.associateBy { it.id })
        entries.forEach { r ->
            val local = rows[r.event.id]
            if (local != null && local.updatedAt > r.event.updatedAt) return@forEach
            if (r.deleted) rows.remove(r.event.id) else rows[r.event.id] = r.event
        }
        return state.copy(children = kids.values.toList(), events = rows.values.toList())
    }
}

/**
 * Field maps for Firestore documents. Same names and units as the local
 * JSON (epoch millis as integers), so the iPhone app can read them later.
 * `syncedAt` (the server's write time) is added by the service.
 */
object SyncDocs {
    const val SCHEMA = 1

    fun entryFields(r: RemoteEntry, uid: String): Map<String, Any?> = with(r.event) {
        mapOf(
            "id" to id, "childId" to childId, "kind" to kind.raw, "startedAt" to startedAt, "endedAt" to endedAt,
            "side" to side, "amount" to amount, "stoolColor" to stoolColor, "note" to note,
            "createdAt" to createdAt, "updatedAt" to updatedAt, "deleted" to r.deleted, "updatedBy" to uid,
        )
    }

    fun childFields(r: RemoteChild, uid: String): Map<String, Any?> = with(r.child) {
        mapOf(
            "id" to id, "name" to name, "birthDate" to birthDate, "createdAt" to createdAt, "lastVisitAt" to lastVisitAt,
            "updatedAt" to updatedAt, "deleted" to r.deleted, "updatedBy" to uid,
        )
    }

    /** Null for a row this build can't read (a kind from a newer app, a damaged row). */
    fun entry(data: Map<String, Any?>): RemoteEntry? {
        val id = data["id"] as? String ?: return null
        val kind = EventKind.fromRaw(data["kind"] as? String) ?: return null
        val startedAt = long(data["startedAt"]) ?: return null
        val createdAt = long(data["createdAt"]) ?: startedAt
        val event = LogEvent(
            id = id,
            childId = data["childId"] as? String ?: return null,
            kind = kind,
            startedAt = startedAt,
            endedAt = long(data["endedAt"]),
            side = data["side"] as? String,
            amount = (data["amount"] as? Number)?.toDouble() ?: 0.0,
            stoolColor = data["stoolColor"] as? String,
            note = data["note"] as? String,
            createdAt = createdAt,
            updatedAt = long(data["updatedAt"]) ?: createdAt,
        )
        return RemoteEntry(event, data["deleted"] == true)
    }

    fun child(data: Map<String, Any?>): RemoteChild? {
        val id = data["id"] as? String ?: return null
        val createdAt = long(data["createdAt"]) ?: return null
        val child = Child(
            id = id,
            name = data["name"] as? String,
            birthDate = long(data["birthDate"]),
            createdAt = createdAt,
            lastVisitAt = long(data["lastVisitAt"]),
            updatedAt = long(data["updatedAt"]) ?: createdAt,
        )
        return RemoteChild(child, data["deleted"] == true)
    }

    private fun long(value: Any?): Long? = (value as? Number)?.toLong()
}

/**
 * Invite codes: eight characters with no 0/O or 1/I to misread, shown as
 * ABCD-2345, sent as a link that opens the app. 32^8 codes, looked up one
 * at a time, so a code can't be found by listing.
 */
object InviteCode {
    const val ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
    const val LENGTH = 8
    const val LINK_BASE = "https://jackwallner.github.io/baby/join.html#"
    const val LIFETIME_MS = 7L * 24 * 3_600_000

    fun generate(random: Random = Random.Default): String =
        (1..LENGTH).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")

    fun isValid(code: String): Boolean = code.length == LENGTH && code.all { it in ALPHABET }

    fun display(code: String): String = code.take(4) + "-" + code.drop(4)

    fun link(code: String): String = LINK_BASE + code

    /**
     * The code in whatever was pasted or opened: the code itself (any case,
     * with or without the dash), the link, the app link, or a whole message
     * containing the link.
     */
    fun parse(text: String?): String? {
        val raw = text?.trim().orEmpty()
        if (raw.isEmpty()) return null
        val candidates = buildList {
            Regex("""(?:#|join/|code=)([A-Za-z0-9-]{8,9})(?![A-Za-z0-9])""").findAll(raw).forEach { add(it.groupValues[1]) }
            add(raw)
            Regex("""[A-Za-z0-9]{4}-?[A-Za-z0-9]{4}""").findAll(raw).forEach { add(it.value) }
        }
        return candidates.asSequence()
            .map { c -> c.uppercase().filter { it.isLetterOrDigit() } }
            .firstOrNull(::isValid)
    }
}
