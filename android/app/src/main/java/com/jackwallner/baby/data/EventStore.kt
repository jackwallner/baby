package com.jackwallner.baby.data

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.util.AtomicFile
import com.jackwallner.baby.model.Child
import com.jackwallner.baby.model.DayTally
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedSide
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.model.LogOps
import com.jackwallner.baby.model.LogState
import com.jackwallner.baby.model.NowSummary
import com.jackwallner.baby.model.RemoteChild
import com.jackwallner.baby.model.RemoteEntry
import com.jackwallner.baby.model.SyncDiff
import com.jackwallner.baby.model.SyncMerge
import java.io.File
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The app's one door to the log: every tap, edit, undo and delete goes
 * through here, and every surface that shows the log reads from here.
 * Saved whole to one file after each change. When logging together is on,
 * each change is also handed to [onCommit] for the shared log, and rows
 * from the shared log come back in through [applyRemote].
 */
class EventStore(
    private val file: File?,
    private val settings: AppSettings,
    private val scope: CoroutineScope,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    /** What the undo toast says, and the log as it was before the action. */
    data class Logged(val kind: EventKind, val message: String, val detail: String?, val before: LogState, val eventId: String?)

    var state by mutableStateOf(load())
        private set
    /** The active baby's entries for the tracked buttons, newest first. */
    var events by mutableStateOf<List<LogEvent>>(emptyList())
        private set
    var summary by mutableStateOf(NowSummary())
        private set
    var lastLogged by mutableStateOf<Logged?>(null)
        private set
    var revision by mutableStateOf(0)
        private set

    /** Reschedules reminders after every change. */
    var onPublish: (NowSummary, Child?) -> Unit = { _, _ -> }

    /** Logging together is on: stamp every change so the shared log's newest-wins rule takes it. */
    var isShared = false
    /** A local change, before and after, for the shared log. */
    var onCommit: (LogState, LogState) -> Unit = { _, _ -> }
    private var lastStamp = 0L

    private var undoJob: Job? = null
    val zone: ZoneId get() = ZoneId.systemDefault()

    val child: Child? get() = state.activeChild
    val children: List<Child> get() = state.children

    init {
        refresh()
    }

    private fun load(): LogState {
        val f = file ?: return LogState()
        return try {
            if (!f.exists()) LogState() else LogState.fromJson(AtomicFile(f).readFully().decodeToString())
        } catch (e: Exception) {
            Log.e("EventStore", "Could not read the log", e)
            LogState()
        }
    }

    /** Strictly increasing, so an undo straight after a delete still lands after it. */
    private fun stampTime(): Long = maxOf(clock(), lastStamp + 1).also { lastStamp = it }

    private fun persist(proposed: LogState, share: Boolean = true): Boolean {
        val before = state
        val next = if (isShared && share) SyncDiff.stamp(before, proposed, stampTime()) else proposed
        val f = file
        if (f != null) {
            val atomic = AtomicFile(f)
            val stream = try { atomic.startWrite() } catch (e: Exception) { return false }
            try {
                stream.write(next.toJson().encodeToByteArray())
                atomic.finishWrite(stream)
            } catch (e: Exception) {
                atomic.failWrite(stream)
                Log.e("EventStore", "Could not save the log", e)
                return false
            }
        }
        state = next
        refresh()
        if (isShared && share) onCommit(before, next)
        return true
    }

    /**
     * Rows from the shared log. The undo snapshot takes them too, so undoing
     * this phone's last tap never takes back someone else's entry.
     */
    fun applyRemote(children: List<RemoteChild>, entries: List<RemoteEntry>) {
        if (children.isEmpty() && entries.isEmpty()) return
        lastLogged?.let { lastLogged = it.copy(before = SyncMerge.merge(it.before, children, entries)) }
        persist(SyncMerge.merge(state, children, entries), share = false)
    }

    /** Rebuilds the visible log and the summary, e.g. after a settings change. */
    fun refresh() {
        val tracked = settings.tracked
        val active = state.activeChild
        events = state.eventsFor(active?.id).filter { tracked.contains(it.kind) }
        summary = NowSummary.make(active, events, clock(), zone, settings.totalsWindow, tracked, settings.diaperWords)
        revision++
        onPublish(summary, active)
    }

    val runningSleep: LogEvent? get() = events.firstOrNull { it.kind == EventKind.SLEEP && it.isRunning }
    val runningFeed: LogEvent? get() = events.firstOrNull { it.kind == EventKind.FEED && it.isRunning }

    fun tally(day: Long): DayTally = DayTally.make(events, day, clock(), zone)

    // MARK: Babies

    fun createChild(name: String?, birthDate: Long?): Boolean {
        val child = Child(name = name?.trim()?.ifEmpty { null }, birthDate = birthDate, createdAt = clock())
        return persist(state.copy(children = state.children + child, activeChildId = child.id))
    }

    fun setActive(child: Child) {
        persist(state.copy(activeChildId = child.id))
    }

    fun updateChild(child: Child, name: String?, birthDate: Long?): Boolean =
        persist(state.copy(children = state.children.map { if (it.id == child.id) it.copy(name = name?.trim()?.ifEmpty { null }, birthDate = birthDate, updatedAt = clock()) else it }))

    fun removeChild(child: Child): Boolean = persist(LogOps.removeChild(state, child.id))

    // MARK: Logging

    private fun remember(kind: EventKind, message: String, detail: String?, before: LogState, eventId: String?) {
        lastLogged = Logged(kind, message, detail, before, eventId)
        undoJob?.cancel()
        undoJob = scope.launch {
            delay(UNDO_WINDOW_MS)
            lastLogged = null
        }
    }

    private fun loggedMessage(kind: EventKind, at: Long): String {
        val name = if (kind == EventKind.FEED) "Feed" else kind.label(settings.diaperWords)
        val now = clock()
        return if (now - at > 90_000) "$name logged at ${Format.time(at, zone)}" else "$name logged"
    }

    fun log(kind: EventKind, at: Long = clock()): LogEvent? {
        val before = state
        val (next, event) = LogOps.log(state, kind, at, clock()) ?: return null
        if (!persist(next)) return null
        remember(kind, loggedMessage(kind, at), null, before, event.id)
        return event
    }

    fun startTimed(kind: EventKind, at: Long = clock()): LogEvent? {
        val before = state
        val (next, event) = LogOps.startTimed(state, kind, at, clock()) ?: return null
        if (!persist(next)) return null
        val message = if (kind == EventKind.SLEEP) "Asleep from ${Format.time(at, zone)}" else loggedMessage(kind, at)
        remember(kind, message, null, before, event.id)
        return event
    }

    fun stopRunning(kind: EventKind, at: Long = clock()): Boolean {
        val before = state
        val next = LogOps.stopRunning(state, kind, at, clock()) ?: return false
        if (!persist(next)) return false
        val message = if (kind == EventKind.SLEEP) "Awake at ${Format.time(at, zone)}" else "Feed finished"
        remember(kind, message, null, before, null)
        return true
    }

    /** Edits the sides of a feed the side chips point at. Not an undoable action of its own. */
    fun setSides(eventId: String, sides: List<FeedSide>): Boolean {
        val event = state.events.firstOrNull { it.id == eventId } ?: return false
        return persist(LogOps.upsert(state, event.withSides(sides), clock()))
    }

    /** Saves an edited or backfilled entry. */
    fun save(event: LogEvent): Boolean {
        val isNew = state.events.none { it.id == event.id }
        val before = state
        if (!persist(LogOps.upsert(state, event, clock()))) return false
        if (isNew) remember(event.kind, loggedMessage(event.kind, event.start), null, before, event.id)
        return true
    }

    /** Deletes an entry and offers Undo, so a stray tap never loses a feed. */
    fun delete(event: LogEvent): Boolean {
        val before = state
        if (!persist(LogOps.delete(state, event.id))) return false
        remember(event.kind, "Entry deleted", null, before, null)
        return true
    }

    /** Puts the log back as it was before the last action. Any later action replaces the undo. */
    fun undoLast(): Boolean {
        val logged = lastLogged ?: return false
        undoJob?.cancel()
        lastLogged = null
        return persist(logged.before)
    }

    fun dismissUndo() {
        undoJob?.cancel()
        lastLogged = null
    }

    /** Debug screenshots: replace the log with a seeded one. */
    fun replaceForDebug(next: LogState) {
        persist(next)
    }

    companion object {
        const val UNDO_WINDOW_MS = 8_000L
    }
}
