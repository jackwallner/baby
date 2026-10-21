package com.jackwallner.baby.model

import org.json.JSONArray
import org.json.JSONObject

/**
 * The whole log on this phone: every baby, every entry, and which baby is
 * active. Small (a busy newborn is about 25 rows a day), so it is kept as one
 * value and saved whole, the way iOS refetches the whole log on every change.
 */
data class LogState(
    val children: List<Child> = emptyList(),
    val events: List<LogEvent> = emptyList(),
    val activeChildId: String? = null,
) {
    val activeChild: Child? get() = children.firstOrNull { it.id == activeChildId } ?: children.firstOrNull()

    fun eventsFor(childId: String?): List<LogEvent> =
        events.filter { it.childId == childId }.sortedByDescending { it.start }

    fun toJson(): String = JSONObject().apply {
        put("version", 1)
        put("activeChildId", activeChildId ?: JSONObject.NULL)
        put("children", JSONArray().apply {
            children.forEach { c ->
                put(JSONObject().apply {
                    put("id", c.id)
                    put("name", c.name ?: JSONObject.NULL)
                    put("birthDate", c.birthDate ?: JSONObject.NULL)
                    put("createdAt", c.createdAt)
                    put("lastVisitAt", c.lastVisitAt ?: JSONObject.NULL)
                    put("updatedAt", c.updatedAt)
                })
            }
        })
        put("events", JSONArray().apply {
            events.forEach { e ->
                put(JSONObject().apply {
                    put("id", e.id)
                    put("childId", e.childId)
                    put("kind", e.kind.raw)
                    put("startedAt", e.startedAt)
                    put("endedAt", e.endedAt ?: JSONObject.NULL)
                    put("side", e.side ?: JSONObject.NULL)
                    put("amount", e.amount)
                    put("stoolColor", e.stoolColor ?: JSONObject.NULL)
                    put("note", e.note ?: JSONObject.NULL)
                    put("createdAt", e.createdAt)
                    put("updatedAt", e.updatedAt)
                })
            }
        })
    }.toString()

    companion object {
        fun fromJson(text: String): LogState {
            val root = JSONObject(text)
            fun JSONObject.longOrNull(key: String): Long? = if (!has(key) || isNull(key)) null else getLong(key)
            fun JSONObject.stringOrNull(key: String): String? = if (!has(key) || isNull(key)) null else getString(key)
            val children = root.optJSONArray("children")?.let { array ->
                (0 until array.length()).map { i ->
                    val c = array.getJSONObject(i)
                    val createdAt = c.getLong("createdAt")
                    Child(c.getString("id"), c.stringOrNull("name"), c.longOrNull("birthDate"), createdAt, c.longOrNull("lastVisitAt"),
                        c.longOrNull("updatedAt") ?: createdAt)
                }
            } ?: emptyList()
            val events = root.optJSONArray("events")?.let { array ->
                (0 until array.length()).mapNotNull { i ->
                    val e = array.getJSONObject(i)
                    // An entry from a newer build with a kind this one does not know is skipped, not crashed on.
                    val kind = EventKind.fromRaw(e.getString("kind")) ?: return@mapNotNull null
                    LogEvent(
                        id = e.getString("id"),
                        childId = e.getString("childId"),
                        kind = kind,
                        startedAt = e.getLong("startedAt"),
                        endedAt = e.longOrNull("endedAt"),
                        side = e.stringOrNull("side"),
                        amount = e.optDouble("amount", 0.0),
                        stoolColor = e.stringOrNull("stoolColor"),
                        note = e.stringOrNull("note"),
                        createdAt = e.getLong("createdAt"),
                        updatedAt = e.getLong("updatedAt"),
                    )
                }
            } ?: emptyList()
            return LogState(children, events, root.stringOrNull("activeChildId"))
        }
    }
}

/**
 * The logging rules, pure, so the JVM tests pin them. Port of the iOS
 * `EventStore` log / startTimed / stopRunning / closeRunning behaviour.
 */
object LogOps {
    /** One tap. A completed feed during a running one ends the running feed. */
    fun log(state: LogState, kind: EventKind, at: Long, now: Long, side: FeedSide? = null): Pair<LogState, LogEvent>? {
        val child = state.activeChild ?: return null
        val closed = if (kind == EventKind.FEED) closeRunning(state.events, child.id, kind, at, now, onlyStartedBefore = true) else state.events
        val event = LogEvent(
            childId = child.id,
            kind = kind,
            startedAt = at,
            endedAt = if (kind == EventKind.FEED) at else null,
            side = if (kind == EventKind.FEED) side?.let { FeedSide.encode(listOf(it)) } else null,
            createdAt = now,
            updatedAt = now,
        )
        return state.copy(events = closed + event) to event
    }

    /** Starts a timed feed or sleep. A running one of the same kind ends first. */
    fun startTimed(state: LogState, kind: EventKind, at: Long, now: Long): Pair<LogState, LogEvent>? {
        if (!kind.canRun) return null
        val child = state.activeChild ?: return null
        val closed = closeRunning(state.events, child.id, kind, at, now, onlyStartedBefore = false)
        val event = LogEvent(childId = child.id, kind = kind, startedAt = at, createdAt = now, updatedAt = now)
        return state.copy(events = closed + event) to event
    }

    /** Ends every running row of the kind (two parents may have started one each). */
    fun stopRunning(state: LogState, kind: EventKind, at: Long, now: Long): LogState? {
        val child = state.activeChild ?: return null
        if (state.events.none { it.childId == child.id && it.kind == kind && it.isRunning }) return null
        return state.copy(events = closeRunning(state.events, child.id, kind, at, now, onlyStartedBefore = false))
    }

    /** A backdated entry from before a timer started leaves that timer alone. */
    private fun closeRunning(events: List<LogEvent>, childId: String, kind: EventKind, at: Long, now: Long, onlyStartedBefore: Boolean) =
        events.map { e ->
            if (e.childId == childId && e.kind == kind && e.isRunning && (!onlyStartedBefore || e.start <= at)) {
                e.copy(endedAt = maxOf(at, e.start), updatedAt = now)
            } else e
        }

    fun upsert(state: LogState, event: LogEvent, now: Long): LogState {
        val updated = event.copy(updatedAt = now)
        val exists = state.events.any { it.id == event.id }
        return state.copy(events = if (exists) state.events.map { if (it.id == event.id) updated else it } else state.events + updated)
    }

    fun delete(state: LogState, id: String): LogState = state.copy(events = state.events.filterNot { it.id == id })

    /** Removes a baby and its log; another baby becomes active. */
    fun removeChild(state: LogState, id: String): LogState {
        val children = state.children.filterNot { it.id == id }
        return LogState(children, state.events.filterNot { it.childId == id },
            if (state.activeChildId == id) children.firstOrNull()?.id else state.activeChildId)
    }
}
