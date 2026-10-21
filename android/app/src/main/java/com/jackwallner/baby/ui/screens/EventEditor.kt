package com.jackwallner.baby.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.ExperimentalComposeUiApi
import com.jackwallner.baby.LocalGraph
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.FeedSide
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.LogEvent
import com.jackwallner.baby.model.StoolColor
import com.jackwallner.baby.ui.Chip
import com.jackwallner.baby.ui.DateDialog
import com.jackwallner.baby.ui.EditorRequest
import com.jackwallner.baby.ui.PrimaryButton
import com.jackwallner.baby.ui.SectionLabel
import com.jackwallner.baby.ui.TextAction
import com.jackwallner.baby.ui.TimeDialog
import com.jackwallner.baby.ui.ValueRow
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder
import java.time.ZoneId

/**
 * One editor for every entry: a new or older one (Log), or an existing one
 * (History). Times, sides, bottle amount, stool colour, weight and a note.
 * Amounts are stored metric and entered the way the parent's doctor talks.
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalComposeUiApi::class)
@Composable
fun EventEditor(request: EditorRequest, onDismiss: () -> Unit) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val zone = ZoneId.systemDefault()
    val words = graph.settings.diaperWords
    val imperial = remember { Format.usesImperial() }
    val existing = request.event
    val kind = existing?.kind ?: request.kind
    val now = remember { System.currentTimeMillis() }
    var start by remember { mutableLongStateOf(existing?.start ?: now) }
    var end by remember { mutableStateOf(existing?.endedAt ?: if (kind == EventKind.SLEEP) null else null) }
    var sides by remember { mutableStateOf(existing?.feedSides ?: emptyList()) }
    var stool by remember { mutableStateOf(existing?.stool) }
    val unitFactor = when (kind) {
        EventKind.WEIGHT -> if (imperial) Format.GRAMS_PER_OUNCE else 1.0
        else -> if (imperial) Format.MILLILITRES_PER_OUNCE else 1.0
    }
    var amountText by remember {
        mutableStateOf(existing?.amount?.takeIf { it > 0 }?.let { Format.oneDecimal(it / unitFactor).removeSuffix(".0") } ?: "")
    }
    var note by remember { mutableStateOf(existing?.note ?: "") }
    var picking by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val amountUnit = when (kind) {
        EventKind.WEIGHT -> if (imperial) "oz" else "g"
        else -> if (imperial) "oz" else "ml"
    }
    val title = (if (existing == null) "Add " else "Edit ") + kind.label(words).lowercase()

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier
                .semantics { testTagsAsResourceId = true }
                .padding(Tokens.margin)
                .fillMaxWidth()
                .graphicBorder(palette)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(Tokens.loose)
                .testTag("editor"),
            verticalArrangement = Arrangement.spacedBy(Tokens.spacing),
        ) {
            Text(title, style = MaterialTheme.typography.titleLarge, color = palette.ink)
            Column(Modifier.fillMaxWidth().background(palette.cardElevated, Tokens.shape)) {
                ValueRow("Date", Format.dayTitle(start, System.currentTimeMillis(), zone), tag = "editor.date") { picking = "date" }
                ValueRow(if (kind.canRun) "Started" else "Time", Format.time(start, zone), tag = "editor.time") { picking = "start" }
                if (kind == EventKind.SLEEP || kind == EventKind.FEED) {
                    val endLabel = end?.let { Format.time(it, zone) } ?: if (kind == EventKind.SLEEP) "Still asleep" else "Not timed"
                    ValueRow("Ended", endLabel, tag = "editor.end") { picking = "end" }
                }
            }
            if (kind == EventKind.FEED) {
                SectionLabel("Side")
                Row(horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                    FeedSide.entries.forEach { side ->
                        Chip(side.label, side in sides, Modifier.weight(1f), color = palette.feed, tag = "editor.side.${side.raw}") {
                            sides = if (side in sides) sides - side else sides + side
                        }
                    }
                }
            }
            if (kind == EventKind.DIRTY) {
                SectionLabel("Color")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Tokens.tight), verticalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                    StoolColor.entries.forEach { c ->
                        Chip(c.label, stool == c, color = palette.dirty, tag = "editor.stool.${c.raw}") { stool = if (stool == c) null else c }
                    }
                }
            }
            if (kind == EventKind.WEIGHT || (kind == EventKind.FEED && FeedSide.BOTTLE in sides)) {
                OutlinedTextField(
                    value = amountText,
                    onValueChange = { amountText = it.filter { ch -> ch.isDigit() || ch == '.' || ch == ',' }.take(7) },
                    label = { Text(if (kind == EventKind.WEIGHT) "Weight ($amountUnit)" else "Bottle amount ($amountUnit)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = palette.accent, focusedLabelColor = palette.accent, cursorColor = palette.accent),
                    modifier = Modifier.fillMaxWidth().testTag("editor.amount"),
                )
            }
            OutlinedTextField(
                value = note,
                onValueChange = { note = it.take(500) },
                label = { Text("Note (optional)") },
                colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = palette.accent, focusedLabelColor = palette.accent, cursorColor = palette.accent),
                modifier = Modifier.fillMaxWidth().testTag("editor.note"),
            )
            error?.let { Text(it, color = palette.notice, style = MaterialTheme.typography.bodySmall) }
            PrimaryButton(if (existing == null) "Log" else "Done", tag = "editor.save") {
                val amount = amountText.replace(',', '.').toDoubleOrNull()?.times(unitFactor) ?: 0.0
                if (kind == EventKind.WEIGHT && amount <= 0) {
                    error = "Enter a weight."
                    return@PrimaryButton
                }
                if (start > System.currentTimeMillis() + 60_000) {
                    error = "That time is in the future."
                    return@PrimaryButton
                }
                val finish = end?.let { maxOf(it, start) } ?: if (kind == EventKind.FEED) start else null
                val base = existing ?: LogEvent(childId = graph.events.child!!.id, kind = kind, startedAt = start, createdAt = System.currentTimeMillis())
                val event = base.copy(
                    startedAt = start,
                    endedAt = finish,
                    side = if (kind == EventKind.FEED) FeedSide.encode(sides) else null,
                    amount = if (kind == EventKind.WEIGHT || (kind == EventKind.FEED && FeedSide.BOTTLE in sides)) amount else 0.0,
                    stoolColor = if (kind == EventKind.DIRTY) stool?.raw else null,
                    note = note.trim().ifEmpty { null },
                )
                if (graph.events.save(event)) onDismiss() else error = "Couldn't save this entry. Please try again."
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                TextAction("Cancel", color = palette.ink2, tag = "editor.cancel") { onDismiss() }
                if (existing != null) {
                    TextAction("Delete", color = palette.notice, tag = "editor.delete") {
                        if (graph.events.delete(existing)) onDismiss()
                    }
                }
            }
        }
    }
    when (picking) {
        "date" -> DateDialog(com.jackwallner.baby.model.DateHelpers.localDate(start, zone), zone, allowFuture = false, onDismiss = { picking = null }) { day ->
            val t = com.jackwallner.baby.model.DateHelpers.zoned(start, zone)
            val moved = day.atTime(t.hour, t.minute).atZone(zone).toInstant().toEpochMilli()
            end = end?.let { it + (moved - start) }
            start = moved
        }
        "start", "end" -> {
            val base = if (picking == "end") end ?: start else start
            val t = com.jackwallner.baby.model.DateHelpers.zoned(base, zone)
            val which = picking
            TimeDialog(t.hour, t.minute, onDismiss = { picking = null }) { h, m ->
                val day = com.jackwallner.baby.model.DateHelpers.zoned(start, zone)
                var value = day.withHour(h).withMinute(m).withSecond(0).withNano(0).toInstant().toEpochMilli()
                if (which == "end") {
                    // An end before the start crosses midnight.
                    if (value < start) value += 24 * 3_600_000L
                    end = value
                } else {
                    start = value
                }
            }
        }
    }
}
