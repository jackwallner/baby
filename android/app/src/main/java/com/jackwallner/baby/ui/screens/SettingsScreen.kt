package com.jackwallner.baby.ui.screens

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Checkroom
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.baby.BuildConfig
import com.jackwallner.baby.LocalGraph
import com.jackwallner.baby.data.Appearance
import com.jackwallner.baby.data.StoreService
import com.jackwallner.baby.model.DateHelpers
import com.jackwallner.baby.model.DiaperWords
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedReminderInterval
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.Guidance
import com.jackwallner.baby.model.StainGuide
import com.jackwallner.baby.model.TotalsWindow
import com.jackwallner.baby.model.TrackedKinds
import com.jackwallner.baby.ui.CapsuleReserve
import com.jackwallner.baby.ui.Chip
import com.jackwallner.baby.ui.DateDialog
import com.jackwallner.baby.ui.Group
import com.jackwallner.baby.ui.Links
import com.jackwallner.baby.ui.NavRow
import com.jackwallner.baby.ui.RowDivider
import com.jackwallner.baby.ui.SectionLabel
import com.jackwallner.baby.ui.SettingsPage
import com.jackwallner.baby.ui.TextAction
import com.jackwallner.baby.ui.ToggleRow
import com.jackwallner.baby.ui.ValueRow
import com.jackwallner.baby.ui.openUrl
import com.jackwallner.baby.ui.theme.CareGraphic
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.launch

@Composable
private fun Page(title: String, onBack: (() -> Unit)? = null, tag: String, content: @Composable ColumnScope.() -> Unit) {
    val palette = LocalPalette.current
    if (onBack != null) BackHandler(onBack = onBack)
    Column(
        Modifier.fillMaxSize().background(palette.paper).verticalScroll(rememberScrollState())
            .padding(horizontal = Tokens.margin).padding(top = Tokens.tight, bottom = CapsuleReserve + Tokens.loose).testTag(tag),
        verticalArrangement = Arrangement.spacedBy(Tokens.loose),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.heightIn(min = 48.dp)) {
            if (onBack != null) {
                IconButton(onClick = onBack, modifier = Modifier.testTag("back").semantics { contentDescription = "Back" }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = palette.accent)
                }
            }
            Text(title, style = MaterialTheme.typography.titleLarge, color = palette.ink)
        }
        content()
    }
}

/** Everything that is not logging: baby, buttons, words, totals, reminders, appearance, guides, Baby+. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SettingsScreen(open: (SettingsPage) -> Unit, onSeePlus: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val context = LocalContext.current
    val settings = graph.settings
    val events = graph.events
    val zone = ZoneId.systemDefault()
    val scope = rememberCoroutineScope()
    val child = events.child ?: return
    var editingName by remember { mutableStateOf(false) }
    var addingBaby by remember { mutableStateOf(false) }
    var pickingBirth by remember { mutableStateOf(false) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }

    Page("Settings", tag = "settings") {
        Group(header = "Guides") {
            NavRow("First Weeks", Icons.Filled.Checklist, tag = "settings.firstWeeks") { open(SettingsPage.FIRST_WEEKS) }
            RowDivider()
            NavRow("Stain helper", Icons.Filled.Checkroom, tag = "settings.stain") { open(SettingsPage.STAIN) }
        }
        Group(header = "Baby") {
            ValueRow("Name", child.name ?: "Add", tag = "settings.name") { editingName = true }
            RowDivider()
            ToggleRow("Born", child.birthDate != null, tag = "settings.born") { born ->
                events.updateChild(child, child.name, if (born) DateHelpers.startOfDay(System.currentTimeMillis(), zone) else null)
            }
            child.birthDate?.let {
                RowDivider()
                ValueRow("Birth date", Format.monthDayYear(it, zone), tag = "settings.birthDate") { pickingBirth = true }
            }
        }
        Group(header = "Babies", footer = "Each baby keeps its own log, its own first-weeks tally and its own summary.") {
            events.children.forEachIndexed { i, baby ->
                if (i > 0) RowDivider()
                ValueRow(baby.displayName, if (baby.id == child.id) "Logging" else "Switch", tag = "settings.baby.$i") {
                    if (baby.id != child.id) events.setActive(baby)
                }
            }
            RowDivider()
            NavRow("Add a baby", tag = "settings.addBaby") { addingBaby = true }
        }
        Group(
            header = "Buttons",
            footer = "A button that is off leaves the home screen, History and reports. What was logged with it is kept, and comes back if you turn it on again.",
        ) {
            TrackedKinds.BUTTONS.forEachIndexed { i, kind ->
                if (i > 0) RowDivider()
                ToggleRow(kind.label(settings.diaperWords), settings.tracked.contains(kind), tag = "settings.button.${kind.raw}",
                    leading = { CareGraphic(kind, size = 32.dp) }) { settings.setTracking(kind, it) }
            }
        }
        Group(header = "Diaper words") {
            Row(Modifier.padding(Tokens.spacing), horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                DiaperWords.entries.forEach { w -> Chip(w.label, settings.diaperWords == w, Modifier.weight(1f), tag = "settings.words.${w.raw}") { settings.updateDiaperWords(w) } }
            }
        }
        Group(header = "Daily totals", footer = "For the totals and hour chart under the buttons. History and reports always use calendar days.") {
            Row(Modifier.padding(Tokens.spacing), horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                val byDay = settings.totalsWindow is TotalsWindow.Day
                Chip("By day", byDay, Modifier.weight(1f), tag = "settings.totals.day") { if (!byDay) settings.updateTotalsWindow(TotalsWindow.MIDNIGHT) }
                Chip("Last 24 hours", !byDay, Modifier.weight(1f), tag = "settings.totals.24h") { settings.updateTotalsWindow(TotalsWindow.Last24Hours) }
            }
            (settings.totalsWindow as? TotalsWindow.Day)?.let { day ->
                RowDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = Tokens.loose, vertical = Tokens.hair), verticalAlignment = Alignment.CenterVertically) {
                    Text("Day starts at", style = MaterialTheme.typography.bodyLarge, color = palette.ink, modifier = Modifier.weight(1f))
                    TextAction("−", tag = "settings.dayStart.earlier") { settings.updateTotalsWindow(TotalsWindow.Day((day.startHour + 23) % 24)) }
                    Text(Format.hourLabel(day.startHour), style = MaterialTheme.typography.labelLarge, color = palette.ink)
                    TextAction("+", tag = "settings.dayStart.later") { settings.updateTotalsWindow(TotalsWindow.Day((day.startHour + 1) % 24)) }
                }
            }
        }
        Group(header = "Reminders") {
            NavRow(
                "Reminders", Icons.Filled.Notifications,
                detail = if (settings.feedInterval == FeedReminderInterval.OFF && !settings.checkupRemindersOn) "Off" else "On",
                tag = "settings.reminders",
            ) { open(SettingsPage.REMINDERS) }
        }
        Group(header = "Appearance", footer = "Night light uses dim, warm colors that are easier on the eyes during feeds in a dark room.") {
            FlowRow(Modifier.padding(Tokens.spacing), horizontalArrangement = Arrangement.spacedBy(Tokens.tight), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                Appearance.entries.forEach { a -> Chip(a.label, settings.appearance == a, tag = "settings.appearance.${a.raw}") { settings.updateAppearance(a) } }
            }
        }
        Group(header = "Baby+") {
            if (graph.store.isPlus) {
                NavRow("Manage subscription", tag = "settings.manage") { context.openUrl(StoreService.MANAGE_URL) }
            } else {
                NavRow("See Baby+", tag = "settings.seePlus") { onSeePlus() }
            }
            RowDivider()
            NavRow("Restore purchases", tag = "settings.restore") { scope.launch { restoreMessage = graph.store.restore() } }
            if (BuildConfig.DEBUG) {
                RowDivider()
                ToggleRow("Local Baby+ override (debug)", settings.debugPlus, tag = "settings.debugPlus") { settings.updateDebugPlus(it) }
            }
        }
        Group(header = "About") {
            NavRow("Rate Baby Tracker", tag = "settings.rate") { context.openUrl(Links.PLAY_LISTING) }
            RowDivider()
            NavRow("Send Feedback", tag = "settings.feedback") { context.openUrl(Links.FEEDBACK) }
            RowDivider()
            NavRow("Support", tag = "settings.support") { context.openUrl(Links.SUPPORT) }
            RowDivider()
            NavRow("Privacy policy", tag = "settings.privacy") { context.openUrl(Links.PRIVACY) }
            RowDivider()
            NavRow("Terms of use", tag = "settings.terms") { context.openUrl(Links.TERMS) }
        }
        Text(Guidance.DISCLAIMER, style = MaterialTheme.typography.bodySmall, color = palette.ink2)
        Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = MaterialTheme.typography.bodySmall, color = palette.ink3)
    }

    if (editingName || addingBaby) {
        var text by remember { mutableStateOf(if (addingBaby) "" else child.name.orEmpty()) }
        AlertDialog(
            onDismissRequest = { editingName = false; addingBaby = false },
            containerColor = palette.card,
            title = { Text(if (addingBaby) "Add a baby" else "Name", color = palette.ink) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                    OutlinedTextField(text, { text = it.take(40) }, singleLine = true, label = { Text("Name (optional)") },
                        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = palette.accent, focusedLabelColor = palette.accent, cursorColor = palette.accent),
                        modifier = Modifier.testTag("settings.nameField"))
                    if (addingBaby) Text("Logging switches to the new baby. Switch back any time under Babies.", style = MaterialTheme.typography.bodySmall, color = palette.ink2)
                }
            },
            confirmButton = {
                TextAction(if (addingBaby) "Add" else "Save", tag = "settings.nameSave") {
                    if (addingBaby) events.createChild(text, null) else events.updateChild(child, text, child.birthDate)
                    editingName = false
                    addingBaby = false
                }
            },
            dismissButton = { TextAction("Cancel", color = palette.ink2) { editingName = false; addingBaby = false } },
        )
    }
    if (pickingBirth) {
        DateDialog(DateHelpers.localDate(child.birthDate ?: System.currentTimeMillis(), zone), zone, allowFuture = false, onDismiss = { pickingBirth = false }) {
            events.updateChild(child, child.name, DateHelpers.dayStartOf(it, zone))
        }
    }
    restoreMessage?.let { message ->
        AlertDialog(onDismissRequest = { restoreMessage = null }, containerColor = palette.card, text = { Text(message, color = palette.ink) },
            confirmButton = { TextAction("OK") { restoreMessage = null } })
    }
}

/** Settings > Reminders: the feed reminder, checkup notes and the next visit date. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RemindersScreen(onBack: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val context = LocalContext.current
    val settings = graph.settings
    val zone = ZoneId.systemDefault()
    var picking by remember { mutableStateOf(false) }
    var denied by remember { mutableStateOf(!graph.reminders.canNotify) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { denied = !it }
    fun ask() {
        if (Build.VERSION.SDK_INT >= 33 && !graph.reminders.canNotify) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
    val anyOn = settings.feedInterval != FeedReminderInterval.OFF || settings.checkupRemindersOn
    Page("Reminders", onBack, tag = "reminders") {
        Group(
            header = "Feed reminder",
            footer = if (denied && anyOn) "Notifications are off for Baby Tracker, so these can't arrive."
            else "On this phone only. The feed reminder counts from when the last feed started. Checkup reminders arrive the evening before the date you add, or before the usual newborn visits when there is a birth date.",
        ) {
            FlowRow(Modifier.padding(Tokens.spacing), horizontalArrangement = Arrangement.spacedBy(Tokens.tight), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                FeedReminderInterval.entries.forEach { interval ->
                    Chip(if (interval == FeedReminderInterval.OFF) "Off" else "Every ${interval.label}", settings.feedInterval == interval, tag = "reminders.${interval.minutes}") {
                        settings.updateFeedInterval(interval)
                        if (interval != FeedReminderInterval.OFF) ask()
                    }
                }
            }
            RowDivider()
            ToggleRow("Checkup reminders", settings.checkupRemindersOn, tag = "reminders.checkups") {
                settings.updateCheckupReminders(it)
                if (it) ask()
            }
            if (settings.checkupRemindersOn) {
                RowDivider()
                ToggleRow("Add next checkup date", settings.nextCheckup != null, tag = "reminders.hasDate") { on ->
                    settings.updateNextCheckup(if (on) DateHelpers.addDays(DateHelpers.startOfDay(System.currentTimeMillis(), zone), 7, zone) + 10 * 3_600_000L else null)
                }
                settings.nextCheckup?.let {
                    RowDivider()
                    ValueRow("Next checkup", Format.monthDayYear(it, zone), tag = "reminders.date") { picking = true }
                }
            }
            if (denied && anyOn) {
                RowDivider()
                NavRow("Allow notifications in Settings", tag = "reminders.allow") {
                    context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
                }
            }
        }
    }
    if (picking) {
        DateDialog(DateHelpers.localDate(settings.nextCheckup ?: System.currentTimeMillis(), zone), zone, allowFuture = true, onDismiss = { picking = false }) {
            settings.updateNextCheckup(it.atTime(10, 0).atZone(zone).toInstant().toEpochMilli())
        }
    }
}

/**
 * The hospital tally sheet, one row per day of life, with the breastfeeding
 * reference beside each day's count and the reasons to call under it. Free,
 * never an assessment of the logged counts.
 */
@Composable
fun FirstWeeksScreen(onBack: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    val child = graph.events.child
    val tracked = graph.settings.tracked
    val now = System.currentTimeMillis()
    Page("First Weeks", onBack, tag = "firstWeeks") {
        Text(Guidance.REFERENCE_SCOPE, style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
        val birth = child?.birthDate
        if (birth == null) {
            Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                Text("Breastfeeding reference by day", style = MaterialTheme.typography.labelLarge, color = palette.ink)
                (1..6).forEach { day ->
                    Row {
                        Text(if (day == 6) "Day 6 on" else "Day $day", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = palette.ink, modifier = Modifier.width(80.dp))
                        Text(Guidance.range(day).summary, style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
                    }
                }
                Text("Add your baby's birth date in Settings and this fills in day by day.", style = MaterialTheme.typography.bodySmall, color = palette.ink2)
            }
        } else {
            Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.spacing).testTag("tallyTable"), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                (1..Guidance.TALLY_DAYS).forEach { day ->
                    val date = DateHelpers.dateForDayOfLife(day, birth, zone)
                    val upcoming = date > now
                    val tally = graph.events.tally(date)
                    val range = Guidance.range(day)
                    val parts = buildList {
                        if (tracked.contains(EventKind.WET)) add("${tally.wet} wet")
                        if (tracked.contains(EventKind.DIRTY)) add("${tally.dirty} dirty")
                        if (tracked.contains(EventKind.FEED)) add("${tally.feeds} feeds")
                    }
                    Column(Modifier.fillMaxWidth()) {
                        Text("Day $day · ${Format.monthDay(date, zone)}", style = MaterialTheme.typography.labelLarge, color = if (upcoming) palette.ink3 else palette.ink)
                        Text(if (upcoming) "Not yet logged" else parts.ifEmpty { listOf("Nothing counted") }.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
                        Text("Breastfeeding reference: ${range.summary}", style = MaterialTheme.typography.bodySmall, color = palette.ink3)
                    }
                    if (day < Guidance.TALLY_DAYS) RowDivider()
                }
            }
        }
        Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose).testTag("callCard"), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
            Text("Call your pediatrician if", style = MaterialTheme.typography.labelLarge, color = palette.ink)
            Guidance.CALL_IF.forEach { line ->
                Row {
                    Text("•", color = palette.ink3)
                    Spacer(Modifier.width(Tokens.tight))
                    Text(line, style = MaterialTheme.typography.bodyMedium, color = palette.ink)
                }
            }
        }
        Text(Guidance.SOURCE_LINE, style = MaterialTheme.typography.bodySmall, color = palette.ink2)
        Column {
            TextAction("NHS breastfeeding reference") { context.openUrl(Guidance.DIAPER_SOURCE) }
            TextAction("AAP feeding guidance") { context.openUrl(Guidance.FEEDING_SOURCE) }
            TextAction("AAP fever guidance") { context.openUrl(Guidance.FEVER_SOURCE) }
        }
        Text(Guidance.DISCLAIMER, style = MaterialTheme.typography.bodySmall, color = palette.ink2)
    }
}

/** What to do about a blowout, spit-up, milk or formula, with only what is at home. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StainHelperScreen(onBack: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val settings = graph.settings
    var stain by remember { mutableStateOf(StainGuide.Stain.BLOWOUT) }
    val owned = settings.stainSupplies
    Page("Stain helper", onBack, tag = "stainHelper") {
        Text(StainGuide.CARE_LABEL_RULE, style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
        SectionLabel("What's at home")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Tokens.tight), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
            StainGuide.Supply.entries.forEach { supply ->
                val on = owned?.contains(supply) == true
                Chip(supply.label, on, tag = "stain.supply.${supply.raw}") {
                    settings.updateStainSupplies(if (on) owned.orEmpty() - supply else owned.orEmpty() + supply)
                }
            }
        }
        SectionLabel("The stain")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Tokens.tight), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
            StainGuide.Stain.entries.forEach { s -> Chip(s.label, stain == s, tag = "stain.${s.raw}") { stain = s } }
        }
        Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.loose), verticalArrangement = Arrangement.spacedBy(Tokens.spacing)) {
            Text("First", style = MaterialTheme.typography.labelLarge, color = palette.accent)
            Text(stain.firstMove, style = MaterialTheme.typography.bodyMedium, color = palette.ink)
            StainGuide.steps(stain, owned.orEmpty()).forEachIndexed { i, step ->
                Column(verticalArrangement = Arrangement.spacedBy(Tokens.hair)) {
                    Text("${i + 1}. ${step.title}", style = MaterialTheme.typography.labelLarge, color = palette.ink)
                    Text(step.detail, style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
                    step.caution?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = palette.notice) }
                }
            }
            val missing = StainGuide.missing(stain, owned.orEmpty())
            if (missing.isNotEmpty()) {
                Text("Worth having for this one: ${missing.joinToString(", ") { it.label.lowercase() }}.", style = MaterialTheme.typography.bodySmall, color = palette.ink2)
            }
        }
        Text(StainGuide.NEVER_RULE, style = MaterialTheme.typography.bodySmall, color = palette.ink2)
    }
}
