package com.jackwallner.baby.data

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import com.jackwallner.baby.model.DiaperWords
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedReminderInterval
import com.jackwallner.baby.model.FeedingStyle
import com.jackwallner.baby.model.StainGuide
import com.jackwallner.baby.model.TotalsWindow
import com.jackwallner.baby.model.TrackedKinds

enum class Appearance(val raw: String, val label: String) {
    SYSTEM("system", "System"),
    LIGHT("light", "Light"),
    DARK("dark", "Dark"),
    /** Dark's layout with dim, warm, low-blue colours for night feeds. */
    NIGHT("night", "Night light");

    companion object {
        fun fromRaw(raw: String?): Appearance = entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

/** Small preferences that are not part of the log. Keys match the iOS App Group keys. */
class AppSettings(private val prefs: SharedPreferences) {
    var hasCompletedSetup by mutableStateOf(prefs.getBoolean("hasCompletedSetup", false))
        private set
    var appearance by mutableStateOf(Appearance.fromRaw(prefs.getString("appearance", null)))
        private set
    var diaperWords by mutableStateOf(DiaperWords.fromRaw(prefs.getString("diaperWords", null)))
        private set
    var tracked by mutableStateOf(readTracked())
        private set
    var totalsWindow by mutableStateOf(
        TotalsWindow.fromStored(if (prefs.contains("totalsWindow")) prefs.getInt("totalsWindow", 0) else null),
    )
        private set
    var feedInterval by mutableStateOf(FeedReminderInterval.fromMinutes(prefs.getInt("reminder.feedMinutes", 0)))
        private set
    var hasOfferedFeedReminder by mutableStateOf(prefs.getBoolean("reminder.offered", false))
        private set
    var checkupRemindersOn by mutableStateOf(prefs.getBoolean("reminder.checkups", false))
        private set
    var nextCheckup by mutableStateOf(prefs.getLong("reminder.nextCheckup", 0L).takeIf { it > 0 })
        private set
    var feedingStyle by mutableStateOf(FeedingStyle.fromRaw(prefs.getString("setup.feedingStyle", null)))
        private set
    var stainSupplies by mutableStateOf(
        prefs.getStringSet("stainSupplies", null)?.mapNotNull(StainGuide.Supply::fromRaw)?.toSet(),
    )
        private set
    /** Debug builds only: the local Baby+ override, like the iOS DEBUG toggle. */
    var debugPlus by mutableStateOf(prefs.getBoolean("debugPlus", false))
        private set

    /** Called after any change that alters the log's summary or reminders. */
    var onChange: () -> Unit = {}

    private fun readTracked(): TrackedKinds =
        TrackedKinds(prefs.getStringSet("hiddenKinds", emptySet()).orEmpty().mapNotNull(EventKind::fromRaw).toSet())

    fun completeSetup() {
        hasCompletedSetup = true
        prefs.edit { putBoolean("hasCompletedSetup", true) }
    }

    fun updateAppearance(value: Appearance) {
        appearance = value
        prefs.edit { putString("appearance", value.raw) }
    }

    fun updateDiaperWords(value: DiaperWords) {
        diaperWords = value
        prefs.edit { putString("diaperWords", value.raw) }
        onChange()
    }

    /** At least one button always stays on. */
    fun setTracking(kind: EventKind, on: Boolean) {
        val hidden = if (on) tracked.hidden - kind else tracked.hidden + kind
        val next = TrackedKinds(hidden)
        if (!on && next.hidden.size != hidden.size) return
        tracked = next
        prefs.edit { putStringSet("hiddenKinds", next.hidden.map { it.raw }.toSet()) }
        onChange()
    }

    fun updateTotalsWindow(value: TotalsWindow) {
        totalsWindow = value
        prefs.edit { putInt("totalsWindow", value.storedValue) }
        onChange()
    }

    fun updateFeedInterval(value: FeedReminderInterval) {
        feedInterval = value
        prefs.edit { putInt("reminder.feedMinutes", value.minutes) }
        onChange()
    }

    fun markFeedReminderOffered() {
        hasOfferedFeedReminder = true
        prefs.edit { putBoolean("reminder.offered", true) }
    }

    fun updateCheckupReminders(on: Boolean) {
        checkupRemindersOn = on
        prefs.edit { putBoolean("reminder.checkups", on) }
        onChange()
    }

    fun updateNextCheckup(value: Long?) {
        nextCheckup = value
        prefs.edit { if (value != null) putLong("reminder.nextCheckup", value) else remove("reminder.nextCheckup") }
        onChange()
    }

    fun updateFeedingStyle(value: FeedingStyle?) {
        feedingStyle = value
        prefs.edit { putString("setup.feedingStyle", value?.raw) }
    }

    fun updateStainSupplies(value: Set<StainGuide.Supply>) {
        stainSupplies = value
        prefs.edit { putStringSet("stainSupplies", value.map { it.raw }.toSet()) }
    }

    fun updateDebugPlus(on: Boolean) {
        debugPlus = on
        prefs.edit { putBoolean("debugPlus", on) }
    }
}
