package com.jackwallner.baby.ui.screens

import android.Manifest
import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.baby.LocalGraph
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedReminderInterval
import com.jackwallner.baby.model.FeedSide
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.NowSummary
import com.jackwallner.baby.model.WindowTotals
import com.jackwallner.baby.ui.CapsuleReserve
import com.jackwallner.baby.ui.Chip
import com.jackwallner.baby.ui.EditorRequest
import com.jackwallner.baby.ui.KindDot
import com.jackwallner.baby.ui.SectionLabel
import com.jackwallner.baby.ui.TextAction
import com.jackwallner.baby.ui.theme.CareGraphic
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.LocalReduceMotion
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder
import java.time.ZoneId
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val SIDE_WINDOW_MS = 90_000L
private const val REMINDER_OFFER_DELAY_MS = 6_000L
private const val CLOCK_RETURN_MS = 60_000L

/**
 * The everyday log: the last feed, the log controls and today's totals, on
 * one screen. The buttons take whatever height the rest leaves, within a
 * floor and a cap; large text scrolls instead.
 */
@Composable
fun LogScreen(onEdit: (EditorRequest) -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val events = graph.events
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(events.revision) {
        while (true) {
            now = System.currentTimeMillis()
            delay(30_000)
        }
    }
    // The log clock: minutes wound back from now, back to now a minute after the last touch.
    var offsetMinutes by rememberSaveable { mutableStateOf(0) }
    var lastTouch by remember { mutableLongStateOf(0L) }
    LaunchedEffect(offsetMinutes, lastTouch) {
        if (offsetMinutes != 0) {
            delay(CLOCK_RETURN_MS)
            offsetMinutes = 0
        }
    }
    val logTime = { System.currentTimeMillis() - offsetMinutes * 60_000L }
    val touched = { lastTouch = System.currentTimeMillis() }
    var showOffer by remember { mutableStateOf(false) }

    val fontScale = LocalDensity.current.fontScale
    BoxWithConstraints(Modifier.fillMaxSize().background(palette.paper)) {
        val large = fontScale > 1.3f
        val tall = maxHeight > 640.dp
        val contentModifier = Modifier
            .widthIn(max = 640.dp)
            .fillMaxWidth()
            .align(Alignment.TopCenter)
            .padding(horizontal = Tokens.margin)
        if (large) {
            Column(
                contentModifier.verticalScroll(rememberScrollState()).padding(top = Tokens.tight, bottom = CapsuleReserve),
                verticalArrangement = Arrangement.spacedBy(Tokens.spacing),
            ) {
                Header(events.summary)
                StatusCard(events.summary, now, logTime)
                LogClockRow(offsetMinutes, now, { offsetMinutes = it; touched() })
                LogButtons(fixedHeight = Tokens.logButtonHeight, logTime = logTime, touched = touched, onEdit = onEdit, onFeedLogged = { showOffer = true })
                TotalsCard(now, showStrip = true)
                OlderEntryLink(onEdit)
            }
        } else {
            Column(
                contentModifier.fillMaxHeight().padding(top = Tokens.tight, bottom = CapsuleReserve),
                verticalArrangement = Arrangement.spacedBy(Tokens.spacing),
            ) {
                Header(events.summary)
                StatusCard(events.summary, now, logTime)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                    LogClockRow(offsetMinutes, now, { offsetMinutes = it; touched() })
                    LogButtons(fixedHeight = null, logTime = logTime, touched = touched, onEdit = onEdit, onFeedLogged = { showOffer = true })
                }
                TotalsCard(now, showStrip = tall)
                OlderEntryLink(onEdit)
            }
        }
    }
    if (showOffer) FeedReminderOffer(onDone = { showOffer = false })
}

@Composable
private fun Header(summary: NowSummary) {
    val palette = LocalPalette.current
    Row(Modifier.fillMaxWidth().heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(summary.childName, style = MaterialTheme.typography.titleLarge, color = palette.ink, modifier = Modifier.weight(1f).testTag("babyName"))
    }
}

/** Leads with the first tracked of feed, diaper, sleep. */
@Composable
private fun StatusCard(summary: NowSummary, now: Long, logTime: () -> Long) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val tracked = graph.settings.tracked
    val zone = ZoneId.systemDefault()
    val lead = when {
        tracked.contains(EventKind.FEED) -> EventKind.FEED
        tracked.tracksDiapers -> summary.lastDiaperKind ?: if (tracked.contains(EventKind.WET)) EventKind.WET else EventKind.DIRTY
        else -> EventKind.SLEEP
    }
    val heading = when {
        lead == EventKind.FEED -> if (summary.isFeeding) "Feeding now" else "Last feed"
        lead.isDiaper -> "Last diaper"
        else -> if (summary.isSleeping) "Asleep" else "Awake"
    }
    val leadTime = when {
        lead == EventKind.FEED -> summary.runningFeedStart?.let { Format.compactDuration((now - it) / 1000.0) }
            ?: summary.lastFeedAt?.let { Format.ago(it, now) } ?: "A fresh start"
        lead.isDiaper -> summary.lastDiaperAt?.let { Format.ago(it, now) } ?: "A fresh start"
        else -> summary.runningSleepStart?.let { Format.compactDuration((now - it) / 1000.0) }
            ?: summary.lastWokeAt?.let { Format.compactDuration((now - it) / 1000.0) } ?: "A fresh start"
    }
    val leadDetail = when {
        lead == EventKind.FEED -> {
            val date = summary.runningFeedStart ?: summary.lastFeedAt
            if (date == null) "Log a first feed below. We'll remember the time and side."
            else {
                val sides = if (summary.isFeeding) summary.runningFeedSides else summary.lastFeedSides
                val label = when (sides.size) {
                    1 -> if (sides[0] == FeedSide.BOTTLE) "Bottle" else "${sides[0].label} breast"
                    else -> FeedSide.label(sides)
                }
                listOfNotNull(label, Format.time(date, zone), summary.nextSideLine).joinToString(" · ")
            }
        }
        lead.isDiaper -> summary.lastDiaperAt?.let { listOfNotNull(summary.lastDiaperKind?.label(summary.words), Format.time(it, zone)).joinToString(" · ") }
            ?: "Log a first diaper below."
        else -> summary.runningSleepStart?.let { "Since ${Format.time(it, zone)}" }
            ?: summary.lastWokeAt?.let { "Woke at ${Format.time(it, zone)}" } ?: "Tap Sleep when the baby falls asleep."
    }
    Column(
        Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.compactCardPadding).testTag("nowCard"),
        verticalArrangement = Arrangement.spacedBy(Tokens.tight),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            KindDot(palette.color(lead))
            Spacer(Modifier.width(Tokens.tight))
            Text(heading, style = MaterialTheme.typography.labelMedium, color = palette.color(lead), modifier = Modifier.weight(1f))
            summary.dayOfLife?.let { Text("Day $it", style = MaterialTheme.typography.labelMedium, color = palette.ink2) }
        }
        Column(Modifier.semantics(mergeDescendants = true) {}) {
            Text(leadTime, style = MaterialTheme.typography.headlineLarge, color = palette.ink, modifier = Modifier.testTag("leadTime"))
            Text(leadDetail, style = MaterialTheme.typography.bodyMedium, color = palette.ink2, modifier = Modifier.testTag("leadDetail"))
        }
        if (lead == EventKind.FEED && summary.isFeeding) {
            TextAction("Finish feed", tag = "finishFeed") { graph.events.stopRunning(EventKind.FEED, logTime()) }
        }
        if (lead == EventKind.FEED && tracked.tracksDiapers) {
            HorizontalDivider(color = palette.cardElevated)
            val diaperKind = summary.lastDiaperKind ?: if (tracked.contains(EventKind.WET)) EventKind.WET else EventKind.DIRTY
            Row(verticalAlignment = Alignment.CenterVertically) {
                KindDot(palette.color(diaperKind))
                Spacer(Modifier.width(Tokens.tight))
                Text(summary.diaperLine(now), style = MaterialTheme.typography.bodyMedium, color = palette.ink2, modifier = Modifier.testTag("diaperLine"))
            }
        }
    }
}

/** "Logging at": minus and plus step five minutes; it returns to now a minute after the last touch. */
@Composable
private fun LogClockRow(offsetMinutes: Int, now: Long, set: (Int) -> Unit) {
    val palette = LocalPalette.current
    val zone = ZoneId.systemDefault()
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.AccessTime, null, tint = palette.ink2, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(Tokens.hair))
        Text("Logging at", style = MaterialTheme.typography.labelMedium, color = palette.ink2)
        Spacer(Modifier.weight(1f))
        IconButton(onClick = { set(offsetMinutes + 5) }, modifier = Modifier.testTag("clock.earlier").semantics { contentDescription = "Five minutes earlier" }) {
            Icon(Icons.Filled.Remove, null, tint = palette.ink)
        }
        Text(
            if (offsetMinutes == 0) "Now" else Format.time(now - offsetMinutes * 60_000L, zone),
            style = MaterialTheme.typography.labelLarge,
            color = if (offsetMinutes == 0) palette.ink else palette.accent,
            modifier = Modifier.testTag("clock.label"),
        )
        IconButton(onClick = { set(maxOf(0, offsetMinutes - 5)) }, enabled = offsetMinutes > 0, modifier = Modifier.testTag("clock.later").semantics { contentDescription = "Five minutes later" }) {
            Icon(Icons.Filled.Add, null, tint = if (offsetMinutes > 0) palette.ink else palette.ink3)
        }
        if (offsetMinutes != 0) TextAction("Now", tag = "clock.now") { set(0) }
    }
}

/**
 * The buttons never move. Feed, then the diaper pair, then Sleep. A tap logs
 * at the log clock's time; a long press opens the editor with the kind.
 */
@Composable
private fun ColumnScope.LogButtons(
    fixedHeight: androidx.compose.ui.unit.Dp?,
    logTime: () -> Long,
    touched: () -> Unit,
    onEdit: (EditorRequest) -> Unit,
    onFeedLogged: () -> Unit,
) {
    val graph = LocalGraph.current
    val tracked = graph.settings.tracked
    val rows = listOf(listOf(EventKind.FEED), listOf(EventKind.WET, EventKind.DIRTY), listOf(EventKind.SLEEP))
        .map { row -> row.filter(tracked::contains) }.filter { it.isNotEmpty() }
    val scope = rememberCoroutineScope()
    var sideTarget by remember { mutableStateOf<String?>(null) }
    var sideJob by remember { mutableStateOf<Job?>(null) }
    var offerJob by remember { mutableStateOf<Job?>(null) }
    val view = LocalView.current
    fun holdSides() {
        sideJob?.cancel()
        sideJob = scope.launch {
            delay(SIDE_WINDOW_MS)
            sideTarget = null
        }
    }
    fun queueOffer() {
        if (graph.settings.hasOfferedFeedReminder || graph.screenshotMode) return
        offerJob?.cancel()
        offerJob = scope.launch {
            delay(REMINDER_OFFER_DELAY_MS)
            if (!graph.settings.hasOfferedFeedReminder) onFeedLogged()
        }
    }
    for (row in rows) {
        val rowModifier = if (fixedHeight != null) Modifier.fillMaxWidth() else Modifier.fillMaxWidth().weight(1f, fill = true)
        Row(rowModifier.heightIn(max = Tokens.maxLogButtonHeight + if (row == listOf(EventKind.FEED) && sideTarget != null) 64.dp else 0.dp), horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
            for (kind in row) {
                val buttonModifier = Modifier.weight(1f).let { if (fixedHeight != null) it.heightIn(min = fixedHeight) else it.fillMaxHeight() }
                if (kind == EventKind.FEED) {
                    FeedCard(
                        modifier = buttonModifier,
                        sideTarget = sideTarget,
                        onTap = {
                            graph.events.log(EventKind.FEED, logTime())?.let {
                                view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                                sideTarget = it.id
                                holdSides()
                                queueOffer()
                                touched()
                            }
                        },
                        onSides = { id, sides ->
                            graph.events.setSides(id, sides)
                            holdSides()
                            if (offerJob?.isActive == true) queueOffer()
                        },
                        onLongPress = { onEdit(EditorRequest(kind = EventKind.FEED)) },
                    )
                } else {
                    KindButton(kind, buttonModifier, onLongPress = { onEdit(EditorRequest(kind = kind)) }) {
                        val ok = if (kind == EventKind.SLEEP) {
                            if (graph.events.runningSleep != null) graph.events.stopRunning(EventKind.SLEEP, logTime())
                            else graph.events.startTimed(EventKind.SLEEP, logTime()) != null
                        } else graph.events.log(kind, logTime()) != null
                        if (ok) {
                            view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                            touched()
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun FeedCard(
    modifier: Modifier,
    sideTarget: String?,
    onTap: () -> Unit,
    onSides: (String, List<FeedSide>) -> Unit,
    onLongPress: () -> Unit,
) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val reduceMotion = LocalReduceMotion.current
    val target = sideTarget?.let { id -> graph.events.events.firstOrNull { it.id == id } }
    Column(
        modifier
            .graphicBorder(palette, fill = palette.fill(EventKind.FEED))
            .clip(Tokens.shape)
            .then(if (reduceMotion) Modifier else Modifier.animateContentSize(spring(dampingRatio = 0.82f, stiffness = 400f))),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .weight(1f, fill = true)
                .heightIn(min = Tokens.minLogButtonHeight)
                .combinedClickable(onClick = onTap, onLongClick = onLongPress, onLongClickLabel = "Add details")
                .semantics { contentDescription = "Feed" }
                .testTag("log.feed"),
            contentAlignment = Alignment.Center,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CareGraphic(EventKind.FEED)
                Spacer(Modifier.width(Tokens.tight))
                Text("Feed", style = MaterialTheme.typography.titleMedium, color = palette.ink)
            }
        }
        AnimatedVisibility(target != null, enter = fadeIn(), exit = fadeOut()) {
            val event = target ?: return@AnimatedVisibility
            Row(
                Modifier.fillMaxWidth().padding(start = Tokens.spacing, end = Tokens.spacing, bottom = Tokens.tight),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Tokens.tight),
            ) {
                Text("Side", style = MaterialTheme.typography.labelMedium, color = palette.ink2)
                val sides = event.feedSides
                FeedSide.entries.forEach { side ->
                    Chip(side.label, side in sides, Modifier.weight(1f), color = palette.feed, tag = "feedSide.${side.raw}") {
                        onSides(event.id, if (side in sides) sides - side else sides + side)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun KindButton(kind: EventKind, modifier: Modifier, onLongPress: () -> Unit, onTap: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val words = graph.settings.diaperWords
    val sleeping = kind == EventKind.SLEEP && graph.events.runningSleep != null
    val label = if (kind == EventKind.SLEEP) (if (sleeping) "Wake" else "Sleep") else kind.label(words)
    Box(
        modifier
            .heightIn(min = Tokens.minLogButtonHeight)
            .graphicBorder(palette, fill = if (sleeping) palette.strongFill(kind) else palette.fill(kind))
            .clip(Tokens.shape)
            .combinedClickable(onClick = onTap, onLongClick = onLongPress, onLongClickLabel = "Add details")
            .semantics { contentDescription = label }
            .testTag("log.${kind.raw}"),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (sleeping) {
                Icon(Icons.Filled.WbSunny, null, tint = palette.sleep, modifier = Modifier.size(Tokens.graphicSize).padding(Tokens.tight))
            } else {
                CareGraphic(kind)
            }
            Spacer(Modifier.width(Tokens.tight))
            Column {
                Text(label, style = MaterialTheme.typography.titleMedium, color = palette.ink)
                graph.events.summary.runningSleepStart?.takeIf { kind == EventKind.SLEEP }?.let {
                    Text(Format.asleep((System.currentTimeMillis() - it) / 1000.0), style = MaterialTheme.typography.bodySmall, color = palette.ink2)
                }
            }
        }
    }
}

/** One figure per button with a kind dot, and the hour strip beneath. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TotalsCard(now: Long, showStrip: Boolean) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val settings = graph.settings
    val totals = WindowTotals.make(graph.events.events, settings.totalsWindow, now, ZoneId.systemDefault())
    val kinds = settings.tracked.buttons
    val title = settings.totalsWindow.title()
    Column(
        Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.compactCardPadding)
            .semantics(mergeDescendants = true) { contentDescription = "$title: ${totals.line(settings.tracked, settings.diaperWords)}" }
            .testTag("todayTotals"),
        verticalArrangement = Arrangement.spacedBy(Tokens.tight),
    ) {
        SectionLabel(title)
        Row(horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
            kinds.forEach { kind ->
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        KindDot(palette.color(kind))
                        Spacer(Modifier.width(Tokens.hair + 2.dp))
                        Text(
                            if (kind == EventKind.SLEEP) (if (totals.sleepSeconds >= 60) Format.compactDuration(totals.sleepSeconds) else "0m") else totals.count(kind).toString(),
                            style = MaterialTheme.typography.titleMedium, color = palette.ink, fontWeight = FontWeight.Bold,
                        )
                    }
                    Text(
                        when (kind) {
                            EventKind.FEED -> if (totals.feeds == 1) "feed" else "feeds"
                            EventKind.SLEEP -> "sleep"
                            else -> kind.label(settings.diaperWords).lowercase()
                        },
                        style = MaterialTheme.typography.bodySmall, color = palette.ink2,
                    )
                }
            }
        }
        if (showStrip) HourStrip(totals, kinds)
    }
}

@Composable
private fun HourStrip(totals: WindowTotals, kinds: List<EventKind>) {
    val palette = LocalPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(Tokens.cellGap), modifier = Modifier.semantics { contentDescription = "Hour by hour" }) {
        kinds.forEach { kind ->
            val values = totals.hours[kind].orEmpty()
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Tokens.cellGap)) {
                KindDot(palette.color(kind), Modifier.size(6.dp))
                Spacer(Modifier.width(Tokens.hair))
                values.forEachIndexed { index, value ->
                    val future = index >= totals.futureFrom
                    val alpha = when {
                        future -> 0f
                        kind == EventKind.SLEEP -> value.toFloat().coerceIn(0f, 1f)
                        value > 0 -> 1f
                        else -> 0f
                    }
                    Box(
                        Modifier
                            .weight(1f)
                            .height(Tokens.cellHeight)
                            .clip(RoundedCornerShape(Tokens.cellRadius))
                            .background(if (future) palette.paper else palette.cardElevated)
                            .background(palette.color(kind).copy(alpha = alpha)),
                    )
                }
            }
        }
    }
}

/** Backfilling lives at the very bottom of Log: Feed, Pee, Poop, Sleep, Weight. */
@Composable
private fun OlderEntryLink(onEdit: (EditorRequest) -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    var open by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        TextAction("Add an older entry", color = palette.ink2, tag = "olderEntry") { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            (graph.settings.tracked.buttons + EventKind.WEIGHT).forEach { kind ->
                DropdownMenuItem(
                    text = { Text(kind.label(graph.settings.diaperWords)) },
                    onClick = { open = false; onEdit(EditorRequest(kind = kind)) },
                    modifier = Modifier.testTag("olderEntry.${kind.raw}"),
                )
            }
        }
    }
}

/** Once per install, a few seconds after a feed: the next feed's reminder. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FeedReminderOffer(onDone: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val settings = graph.settings
    var choice by remember { mutableStateOf(settings.feedingStyle?.suggestedInterval ?: FeedReminderInterval.TWO_AND_A_HALF_HOURS) }
    var checkups by remember { mutableStateOf(true) }
    fun accept() {
        settings.updateFeedInterval(choice)
        settings.updateCheckupReminders(checkups)
        settings.markFeedReminderOffered()
        onDone()
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { accept() }
    androidx.compose.material3.AlertDialog(
        onDismissRequest = { settings.markFeedReminderOffered(); onDone() },
        containerColor = palette.card,
        title = { Text("Remind you about the next feed?", color = palette.ink) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Tokens.spacing)) {
                Text("A nudge on this phone, counted from when the last feed started, with the side to start on.", color = palette.ink2, style = MaterialTheme.typography.bodyMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Tokens.tight), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                    FeedReminderInterval.CHOICES.forEach {
                        Chip(it.shortLabel, choice == it, tag = "offer.${it.minutes}") { choice = it }
                    }
                }
                com.jackwallner.baby.ui.ToggleRow("Before checkups too", checkups, tag = "offer.checkups") { checkups = it }
                Text("The evening before a newborn visit, a note that your summary for the doctor is ready.", color = palette.ink2, style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = {
            TextAction("Turn on reminders", tag = "offer.accept") {
                if (Build.VERSION.SDK_INT >= 33 && !graph.reminders.canNotify) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else accept()
            }
        },
        dismissButton = { TextAction("Not now", color = palette.ink2, tag = "offer.decline") { settings.markFeedReminderOffered(); onDone() } },
    )
}
