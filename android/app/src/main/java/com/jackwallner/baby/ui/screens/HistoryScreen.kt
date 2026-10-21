package com.jackwallner.baby.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.baby.LocalGraph
import com.jackwallner.baby.model.DateHelpers
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.ui.CapsuleReserve
import com.jackwallner.baby.ui.EditorRequest
import com.jackwallner.baby.ui.KindDot
import com.jackwallner.baby.ui.SectionLabel
import com.jackwallner.baby.ui.TextAction
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder
import java.time.ZoneId
import kotlinx.coroutines.launch

/**
 * The full log, free: Today and Yesterday tiles, a 14-day chart (Baby+;
 * blurred under a lock for free users) and every entry by day. Tap an entry to
 * edit or delete it.
 */
@Composable
fun HistoryScreen(onEdit: (EditorRequest) -> Unit, onUnlock: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val zone = ZoneId.systemDefault()
    val now = System.currentTimeMillis()
    val events = graph.events.events
    val words = graph.settings.diaperWords
    val groups = remember(graph.events.revision) {
        events.groupBy { DateHelpers.startOfDay(it.start, zone) }.toSortedMap(compareByDescending { it }).toList()
    }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var addOpen by remember { mutableStateOf(false) }
    val today = DateHelpers.startOfDay(now, zone)
    val yesterday = DateHelpers.addDays(today, -1, zone)

    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize().background(palette.paper).testTag("historyList"),
        contentPadding = PaddingValues(start = Tokens.margin, end = Tokens.margin, top = Tokens.tight, bottom = CapsuleReserve + Tokens.loose),
        verticalArrangement = Arrangement.spacedBy(Tokens.tight),
    ) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("History", style = MaterialTheme.typography.titleLarge, color = palette.ink, modifier = Modifier.weight(1f))
                Box {
                    IconButton(onClick = { addOpen = true }, modifier = Modifier.testTag("history.add").semantics { contentDescription = "Add an entry" }) {
                        Icon(Icons.Filled.Add, null, tint = palette.accent)
                    }
                    DropdownMenu(addOpen, onDismissRequest = { addOpen = false }) {
                        (graph.settings.tracked.buttons + EventKind.WEIGHT).forEach { kind ->
                            DropdownMenuItem(text = { Text(kind.label(words)) }, onClick = { addOpen = false; onEdit(EditorRequest(kind = kind)) })
                        }
                    }
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                listOf("Today" to today, "Yesterday" to yesterday).forEach { (label, day) ->
                    DayTile(label, day, Modifier.weight(1f)) {
                        val index = groups.indexOfFirst { it.first == day }
                        if (index >= 0) scope.launch { listState.animateScrollToItem(headerIndex(groups, index)) }
                    }
                }
            }
        }
        item { DayChart(onUnlock) }
        if (groups.isEmpty()) {
            item {
                Text("Nothing logged yet. Entries appear here as you log them.", color = palette.ink2, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(vertical = Tokens.loose))
            }
        }
        groups.forEach { (day, dayEvents) ->
            item(key = "day-$day") {
                val tally = graph.events.tally(day)
                val parts = buildList {
                    if (graph.settings.tracked.contains(EventKind.FEED)) add(Format.count(tally.feeds, "feed"))
                    if (graph.settings.tracked.contains(EventKind.WET)) add("${tally.wet} ${EventKind.WET.label(words).lowercase()}")
                    if (graph.settings.tracked.contains(EventKind.DIRTY)) add("${tally.dirty} ${EventKind.DIRTY.label(words).lowercase()}")
                    if (graph.settings.tracked.contains(EventKind.SLEEP) && tally.sleepSeconds >= 60) add("${Format.compactDuration(tally.sleepSeconds)} sleep")
                }
                Column(Modifier.padding(top = Tokens.spacing)) {
                    Text(Format.dayTitle(day, now, zone), style = MaterialTheme.typography.titleMedium, color = palette.ink)
                    Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = palette.ink2)
                }
            }
            items(dayEvents, key = { it.id }) { event -> EntryRow(event, now) { onEdit(EditorRequest(event = event)) } }
        }
    }
}

/** The LazyColumn index of a day's header: three fixed items, then a header and its rows per day. */
private fun headerIndex(groups: List<Pair<Long, List<LogEvent>>>, dayIndex: Int): Int =
    3 + groups.take(dayIndex).sumOf { 1 + it.second.size }

@Composable
private fun DayTile(label: String, day: Long, modifier: Modifier, onClick: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val tally = graph.events.tally(day)
    val tracked = graph.settings.tracked
    Column(
        modifier.graphicBorder(palette).clip(Tokens.shape).clickable(role = Role.Button, onClick = onClick).padding(Tokens.spacing)
            .testTag("history.tile.${label.lowercase()}"),
        verticalArrangement = Arrangement.spacedBy(Tokens.hair),
    ) {
        SectionLabel(label)
        tracked.buttons.forEach { kind ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                KindDot(palette.color(kind))
                Spacer(Modifier.width(Tokens.hair + 2.dp))
                val value = when (kind) {
                    EventKind.FEED -> Format.count(tally.feeds, "feed")
                    EventKind.WET -> "${tally.wet} ${kind.label(graph.settings.diaperWords).lowercase()}"
                    EventKind.DIRTY -> "${tally.dirty} ${kind.label(graph.settings.diaperWords).lowercase()}"
                    else -> "${Format.compactDuration(tally.sleepSeconds)} sleep"
                }
                Text(value, style = MaterialTheme.typography.bodyMedium, color = palette.ink)
            }
        }
    }
}

/** Feeds per day over 14 days. Drag to read a day. Baby+; free users see their own bars blurred. */
@Composable
private fun DayChart(onUnlock: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val zone = ZoneId.systemDefault()
    val now = System.currentTimeMillis()
    val isPlus = graph.store.isPlus
    val today = DateHelpers.startOfDay(now, zone)
    val days = (13 downTo 0).map { DateHelpers.addDays(today, -it.toLong(), zone) }
    val kind = graph.settings.tracked.buttons.firstOrNull { it != EventKind.SLEEP } ?: EventKind.SLEEP
    // Blur needs API 31; below it a locked chart shows a neutral shape, not the baby's numbers.
    val hideNumbers = !isPlus && android.os.Build.VERSION.SDK_INT < 31
    val values = if (hideNumbers) days.indices.map { 4.0 + (it * 7 % 5) } else days.map { day ->
        val t = graph.events.tally(day)
        when (kind) {
            EventKind.FEED -> t.feeds.toDouble()
            EventKind.WET -> t.wet.toDouble()
            EventKind.DIRTY -> t.dirty.toDouble()
            else -> t.sleepSeconds / 3600
        }
    }
    var selected by remember { mutableStateOf<Int?>(null) }
    val maxValue = (values.maxOrNull() ?: 0.0).coerceAtLeast(1.0)
    val kindName = when (kind) {
        EventKind.FEED -> "Feeds"
        EventKind.SLEEP -> "Sleep hours"
        else -> kind.label(graph.settings.diaperWords)
    }
    Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.spacing).testTag("history.chart"), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
        val header = selected?.let { "${Format.dayTitle(days[it], now, zone)}: ${if (kind == EventKind.SLEEP) Format.compactDuration(values[it] * 3600) else values[it].toInt().toString()}" }
            ?: "$kindName, last 14 days"
        Text(if (isPlus) header else "$kindName, last 14 days", style = MaterialTheme.typography.labelLarge, color = palette.ink)
        Box(Modifier.fillMaxWidth().height(96.dp)) {
            Canvas(
                Modifier
                    .fillMaxSize()
                    .then(if (isPlus) Modifier else Modifier.blur(Tokens.previewBlur))
                    .pointerInput(isPlus) {
                        if (!isPlus) return@pointerInput
                        detectHorizontalDragGestures(onDragEnd = { selected = null }) { change, _ ->
                            selected = (change.position.x / size.width * days.size).toInt().coerceIn(0, days.size - 1)
                        }
                    },
            ) {
                val slot = size.width / days.size
                values.forEachIndexed { i, v ->
                    val h = (v / maxValue * size.height).toFloat()
                    drawRoundRect(
                        palette.color(kind).copy(alpha = if (i == days.size - 1) Tokens.PARTIAL_BAR_ALPHA else if (selected == null || selected == i) 1f else 0.5f),
                        topLeft = Offset(i * slot + slot * 0.18f, size.height - h),
                        size = Size(slot * 0.64f, h),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()),
                    )
                }
            }
            if (!isPlus) {
                Row(
                    Modifier.align(Alignment.Center).clip(Tokens.shape).background(palette.card).clickable(role = Role.Button, onClick = onUnlock)
                        .heightIn(min = Tokens.minTouch).padding(horizontal = Tokens.spacing).testTag("history.chart.unlock"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Lock, null, tint = palette.accent, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(Tokens.hair))
                    Text("Trends with Baby+", style = MaterialTheme.typography.labelLarge, color = palette.ink)
                }
            }
        }
    }
}

@Composable
private fun EntryRow(event: LogEvent, now: Long, onClick: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val zone = ZoneId.systemDefault()
    val words = graph.settings.diaperWords
    val title = when {
        event.kind == EventKind.FEED && event.isRunning -> "Feeding"
        else -> event.kind.label(words)
    }
    val detail = listOfNotNull(event.detailText(Format.usesImperial()), event.note?.takeIf { it.isNotBlank() }).joinToString(" · ")
    Row(
        Modifier.fillMaxWidth().graphicBorder(palette, radius = 16.dp).clip(Tokens.shape).clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = 56.dp).padding(horizontal = Tokens.spacing, vertical = Tokens.tight).testTag("entry.${event.kind.raw}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        KindDot(palette.color(event.kind))
        Spacer(Modifier.width(Tokens.spacing))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = palette.ink)
            if (detail.isNotEmpty()) Text(detail, style = MaterialTheme.typography.bodySmall, color = palette.ink2, maxLines = 2)
        }
        Text(Format.time(event.start, zone), style = MaterialTheme.typography.bodyMedium, color = palette.ink2)
    }
}
