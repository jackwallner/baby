package com.jackwallner.baby

import android.content.Intent
import com.jackwallner.baby.data.Appearance
import com.jackwallner.baby.model.Child
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.model.LogState
import com.jackwallner.baby.model.StoolColor
import java.time.LocalDate
import java.time.ZoneId

/**
 * Debug-only launch extras for tests and screenshots, the Android side of the
 * iOS launch arguments. None of this is compiled into a release build.
 *
 *     adb shell am start -n com.jackwallner.baby/.MainActivity \
 *         --ez seed true --ei tab 0 --es appearance night
 *
 * `seed` (`-SeedScreenshotData`) replaces the log with a day-three newborn,
 * `empty` (`-EmptyLog`) clears it for the reviewer's no-data path, `tab`
 * (`-StartTab`) opens Log, History, Upgrade/Reports or Settings, `plus`
 * turns the local Baby+ override on or off, and `screenshot` hides the
 * reminder offer and records no paywall impressions.
 */
object DebugLaunchOptions {
    fun apply(graph: AppGraph, intent: Intent?): Int? {
        val extras = intent?.extras ?: return null
        extras.getString("appearance")?.let { graph.settings.updateAppearance(Appearance.fromRaw(it)) }
        if (extras.containsKey("plus")) graph.settings.updateDebugPlus(extras.getBoolean("plus"))
        if (extras.getBoolean("screenshot")) {
            graph.screenshotMode = true
            graph.store.suppressImpressions = true
        }
        if (extras.getBoolean("seed")) {
            graph.events.replaceForDebug(seed(System.currentTimeMillis(), ZoneId.systemDefault()))
            graph.settings.completeSetup()
        }
        if (extras.getBoolean("empty")) {
            graph.events.replaceForDebug(LogState(listOf(Child(id = "empty")), emptyList(), "empty"))
            graph.settings.completeSetup()
        }
        return if (extras.containsKey("tab")) extras.getInt("tab") else null
    }

    /** A day-three newborn (born two days ago), with the last feed 1h 40m ago. */
    fun seed(now: Long, zone: ZoneId): LogState {
        val today = LocalDate.now(zone)
        val birth = today.minusDays(2).atTime(4, 12).atZone(zone).toInstant().toEpochMilli()
        val child = Child(id = "seed", name = "Elsa", birthDate = birth, createdAt = birth)
        val events = mutableListOf<LogEvent>()
        var n = 0
        fun at(daysAgo: Long, h: Int, m: Int) = today.minusDays(daysAgo).atTime(h, m).atZone(zone).toInstant().toEpochMilli()
        fun add(kind: EventKind, start: Long, end: Long? = null, side: String? = null, amount: Double = 0.0, stool: StoolColor? = null) {
            if (start > now) return
            n++
            events += LogEvent(id = "seed-$n", childId = child.id, kind = kind, startedAt = start, endedAt = end ?: if (kind == EventKind.FEED) start else null,
                side = side, amount = amount, stoolColor = stool?.raw, createdAt = start, updatedAt = start)
        }
        add(EventKind.WEIGHT, at(2, 9, 0), amount = 3400.0)
        for (daysAgo in 2L downTo 1L) {
            listOf(1 to 10, 4 to 0, 6 to 45, 9 to 30, 12 to 15, 15 to 0, 17 to 40, 20 to 20, 22 to 50).forEachIndexed { i, (h, m) ->
                add(EventKind.FEED, at(daysAgo, h, m), end = at(daysAgo, h, m) + 25 * 60_000L, side = if (i % 2 == 0) "left" else "right,left")
            }
            listOf(2, 7, 11, 14, 19, 23).take(if (daysAgo == 2L) 3 else 5).forEach { add(EventKind.WET, at(daysAgo, it, 5)) }
            add(EventKind.DIRTY, at(daysAgo, 10, 0), stool = if (daysAgo == 2L) StoolColor.BLACK else StoolColor.GREEN)
            add(EventKind.DIRTY, at(daysAgo, 18, 30), stool = if (daysAgo == 2L) StoolColor.GREEN else StoolColor.YELLOW)
            add(EventKind.SLEEP, at(daysAgo, 13, 0), end = at(daysAgo, 14, 50))
        }
        add(EventKind.WEIGHT, at(1, 9, 0), amount = 3310.0)
        // Today, relative to now so the hero line always reads the same.
        val hour = 3_600_000L
        add(EventKind.FEED, now - 6 * hour - 20 * 60_000, side = "left")
        add(EventKind.WET, now - 5 * hour)
        add(EventKind.FEED, now - 4 * hour - 10 * 60_000, end = now - 3 * hour - 45 * 60_000, side = "right,left")
        add(EventKind.DIRTY, now - 3 * hour, stool = StoolColor.YELLOW)
        add(EventKind.SLEEP, now - 3 * hour + 10 * 60_000, end = now - 2 * hour)
        add(EventKind.FEED, now - 100 * 60_000, end = now - 80 * 60_000, side = "left,right")
        add(EventKind.WET, now - 48 * 60_000)
        return LogState(listOf(child), events, child.id)
    }
}
