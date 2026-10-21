package com.jackwallner.baby.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.baby.LocalGraph
import com.jackwallner.baby.data.Exports
import com.jackwallner.baby.model.DateHelpers
import com.jackwallner.baby.model.EventKind
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.SummaryReport
import com.jackwallner.baby.ui.CapsuleReserve
import com.jackwallner.baby.ui.Chip
import com.jackwallner.baby.ui.Group
import com.jackwallner.baby.ui.NavRow
import com.jackwallner.baby.ui.RowDivider
import com.jackwallner.baby.ui.SectionLabel
import com.jackwallner.baby.ui.theme.LocalPalette
import com.jackwallner.baby.ui.theme.Tokens
import com.jackwallner.baby.ui.theme.graphicBorder
import java.time.ZoneId

/**
 * Baby+ Reports: a 7 / 14 / 30 day range, daily averages per button with one
 * supporting figure, one chart per kind with a dashed average line, then the
 * pediatrician PDF and the CSV. Ranges never start before the first entry.
 */
@Composable
fun ReportsScreen() {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    val child = graph.events.child ?: return
    var days by rememberSaveable { mutableStateOf(7) }
    val now = System.currentTimeMillis()
    val events = graph.events.events
    val imperial = remember { Format.usesImperial() }
    val report = remember(graph.events.revision, days) {
        val first = events.minOfOrNull { it.start } ?: now
        val from = maxOf(DateHelpers.addDays(DateHelpers.startOfDay(now, zone), -(days - 1).toLong(), zone), DateHelpers.startOfDay(first, zone))
        SummaryReport.make(child.displayName, child.birthDate, events, from, now, graph.settings.tracked, now, zone)
    }
    val tracked = graph.settings.tracked
    Column(
        Modifier.fillMaxSize().background(palette.paper).verticalScroll(rememberScrollState())
            .padding(horizontal = Tokens.margin).padding(top = Tokens.tight, bottom = CapsuleReserve + Tokens.loose).testTag("reports"),
        verticalArrangement = Arrangement.spacedBy(Tokens.spacing),
    ) {
        Text("Reports", style = MaterialTheme.typography.titleLarge, color = palette.ink)
        Row(horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
            listOf(7, 14, 30).forEach { n -> Chip("$n days", days == n, Modifier.weight(1f), tag = "range.$n") { days = n } }
        }
        Text(report.rangeLabel(), style = MaterialTheme.typography.bodySmall, color = palette.ink2)
        val tiles = buildList {
            if (tracked.contains(EventKind.FEED)) add(Triple(EventKind.FEED, "${Format.oneDecimal(report.averageFeedsPerDay)} feeds", "longest gap ${Format.compactDuration(report.longestFeedGapSeconds)}"))
            if (tracked.contains(EventKind.WET)) add(Triple(EventKind.WET, "${Format.oneDecimal(report.averageWetPerDay)} wet", report.lowestDay { it.wet }?.let { "lowest day ${it.wet}" } ?: ""))
            if (tracked.contains(EventKind.DIRTY)) add(Triple(EventKind.DIRTY, "${Format.oneDecimal(report.averageDirtyPerDay)} dirty", report.lowestDay { it.dirty }?.let { "lowest day ${it.dirty}" } ?: ""))
            if (tracked.contains(EventKind.SLEEP)) add(Triple(EventKind.SLEEP, "${Format.compactDuration(report.averageSleepSeconds)} sleep", "longest stretch ${Format.compactDuration(report.longestSleepSeconds)}"))
        }
        SectionLabel("Daily averages")
        tiles.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.tight)) {
                pair.forEach { (kind, value, second) ->
                    Column(Modifier.weight(1f).graphicBorder(palette).padding(Tokens.spacing)) {
                        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = palette.color(kind))
                        Text(second, style = MaterialTheme.typography.bodySmall, color = palette.ink2)
                    }
                }
                if (pair.size == 1) Column(Modifier.weight(1f)) {}
            }
        }
        report.weightChangeDescription(imperial)?.let { Text("Weight: $it", style = MaterialTheme.typography.bodyMedium, color = palette.ink) }
        Text(report.averagesNote(), style = MaterialTheme.typography.bodySmall, color = palette.ink2, modifier = Modifier.testTag("reports.note"))
        tracked.buttons.forEach { kind -> KindChart(report, kind) }
        Group(header = "For the doctor") {
            NavRow("Pediatrician summary (PDF)", Icons.Filled.Description, tag = "reports.pdf") {
                val file = Exports.writePdf(context, report, imperial)
                Exports.share(context, file, "application/pdf", "${child.displayName} summary")
            }
            RowDivider()
            NavRow("Every entry (CSV)", Icons.Filled.TableChart, tag = "reports.csv") {
                val all = graph.events.state.eventsFor(child.id)
                val file = Exports.writeCsv(context, SummaryReport.csv(all, child.displayName, zone), child.displayName)
                Exports.share(context, file, "text/csv", "${child.displayName} log")
            }
        }
        PlusActiveCard()
    }
}

@Composable
private fun KindChart(report: SummaryReport, kind: EventKind) {
    val graph = LocalGraph.current
    val palette = LocalPalette.current
    val values = report.days.map {
        when (kind) {
            EventKind.FEED -> it.feeds.toDouble()
            EventKind.WET -> it.wet.toDouble()
            EventKind.DIRTY -> it.dirty.toDouble()
            else -> it.sleepSeconds / 3600
        }
    }
    val average = when (kind) {
        EventKind.FEED -> report.averageFeedsPerDay
        EventKind.WET -> report.averageWetPerDay
        EventKind.DIRTY -> report.averageDirtyPerDay
        else -> report.averageSleepSeconds / 3600
    }
    val title = when (kind) {
        EventKind.FEED -> "Feeds per day"
        EventKind.SLEEP -> "Sleep per day"
        else -> "${kind.label(graph.settings.diaperWords)} diapers per day"
    }
    val takeaway = when (kind) {
        EventKind.SLEEP -> "About ${Format.compactDuration(average * 3600)} a day on complete days."
        else -> "About ${Format.oneDecimal(average)} a day on complete days."
    }
    Column(Modifier.fillMaxWidth().graphicBorder(palette).padding(Tokens.spacing).testTag("chart.${kind.raw}"), verticalArrangement = Arrangement.spacedBy(Tokens.hair)) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = palette.ink)
        Text(takeaway, style = MaterialTheme.typography.bodySmall, color = palette.ink2)
        val maxValue = (values.maxOrNull() ?: 0.0).coerceAtLeast(average).coerceAtLeast(1.0)
        Canvas(Modifier.fillMaxWidth().height(Tokens.chartHeight).padding(top = Tokens.tight)) {
            val slot = size.width / values.size.coerceAtLeast(1)
            values.forEachIndexed { i, v ->
                val h = (v / maxValue * size.height).toFloat()
                val partial = !report.days[i].isComplete
                drawRoundRect(
                    palette.color(kind).copy(alpha = if (partial) Tokens.PARTIAL_BAR_ALPHA else 1f),
                    topLeft = Offset(i * slot + slot * 0.18f, size.height - h),
                    size = Size(slot * 0.64f, h),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()),
                )
            }
            val y = (size.height - average / maxValue * size.height).toFloat()
            drawLine(palette.ink2, Offset(0f, y), Offset(size.width, y), strokeWidth = 1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f)))
        }
    }
}
