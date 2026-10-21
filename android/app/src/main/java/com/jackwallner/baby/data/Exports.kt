package com.jackwallner.baby.data

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import androidx.core.content.FileProvider
import com.jackwallner.baby.model.Format
import com.jackwallner.baby.model.SummaryReport
import java.io.File

/**
 * The pediatrician summary as a PDF (A4/Letter-neutral 612 x 792 points) and
 * the CSV, written to the cache and shared through the system sheet. Both
 * read the same [SummaryReport], so the page and the export cannot disagree.
 */
object Exports {
    private fun dir(context: Context) = File(context.cacheDir, "exports").apply { mkdirs() }

    private fun safeName(name: String) = name.filter { it.isLetterOrDigit() || it == ' ' || it == '-' }.trim().replace(' ', '-')

    fun writeCsv(context: Context, csv: String, childName: String): File =
        File(dir(context), "${safeName(childName).ifEmpty { "baby" }}-log.csv").apply { writeText(csv) }

    fun share(context: Context, file: File, mime: String, title: String) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.exports", file)
        val send = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri).putExtra(Intent.EXTRA_SUBJECT, title)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(send, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun writePdf(context: Context, report: SummaryReport, imperial: Boolean): File {
        val doc = PdfDocument()
        val width = 612
        val height = 792
        val margin = 40f
        val ink = Paint().apply { color = Color.rgb(28, 26, 23); isAntiAlias = true; textSize = 10f }
        val ink2 = Paint(ink).apply { color = Color.rgb(107, 102, 97) }
        val bold = Paint(ink).apply { typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD) }
        val title = Paint(bold).apply { textSize = 18f }
        val rule = Paint().apply { color = Color.rgb(217, 212, 204); strokeWidth = 0.75f }
        var pageNumber = 1
        var page = doc.startPage(PdfDocument.PageInfo.Builder(width, height, pageNumber).create())
        var canvas = page.canvas
        var y = margin + 10

        fun footer() {
            canvas.drawText("Kept in Baby Tracker by the parent. A log of what was recorded, not medical advice.", margin, height - 24f, ink2)
            canvas.drawText("page $pageNumber", width - margin - 40, height - 24f, ink2)
        }
        fun newPageIfNeeded(need: Float) {
            if (y + need < height - 48) return
            footer()
            doc.finishPage(page)
            pageNumber++
            page = doc.startPage(PdfDocument.PageInfo.Builder(width, height, pageNumber).create())
            canvas = page.canvas
            y = margin + 10
        }

        canvas.drawText("${report.childName}: ${report.tracked.headline.lowercase()}", margin, y, title)
        y += 18
        val born = report.birthDate?.let { " · born ${Format.monthDayYear(it, report.zone)}" } ?: ""
        canvas.drawText("${report.rangeLabel()} · ${Format.count(report.dayCount, "day")}$born", margin, y, ink2)
        y += 24

        // The figures a doctor asks first, each with its second number.
        val stats = buildList {
            if (report.tracked.contains(com.jackwallner.baby.model.EventKind.FEED)) {
                add("feeds / day" to Format.oneDecimal(report.averageFeedsPerDay) + "  longest gap ${Format.compactDuration(report.longestFeedGapSeconds)}")
            }
            if (report.tracked.contains(com.jackwallner.baby.model.EventKind.WET)) {
                add("wet / day" to Format.oneDecimal(report.averageWetPerDay) + (report.lowestDay { it.wet }?.let { "  lowest day ${it.wet}, ${Format.monthDay(it.date, report.zone)}" } ?: ""))
            }
            if (report.tracked.contains(com.jackwallner.baby.model.EventKind.DIRTY)) {
                add("dirty / day" to Format.oneDecimal(report.averageDirtyPerDay) + (report.lowestDay { it.dirty }?.let { "  lowest day ${it.dirty}, ${Format.monthDay(it.date, report.zone)}" } ?: ""))
            }
            if (report.tracked.contains(com.jackwallner.baby.model.EventKind.SLEEP)) {
                add("sleep / day" to Format.compactDuration(report.averageSleepSeconds) + "  longest stretch ${Format.compactDuration(report.longestSleepSeconds)}")
            }
            if (report.averageBottleMillilitresPerDay > 0) {
                add("bottle / day" to Format.millilitres(report.averageBottleMillilitresPerDay, imperial) + "  about ${Format.millilitres(report.averageBottleMillilitresPerFeed, imperial)} a bottle")
            }
            add("weight" to (report.latestWeight?.let { Format.grams(it, imperial) + "  " + (report.weightChangeDescription(imperial) ?: "") } ?: "no weigh-ins in this range"))
        }
        for ((label, value) in stats) {
            canvas.drawText(label.uppercase(), margin, y, ink2)
            canvas.drawText(value, margin + 110, y, bold)
            y += 15
        }
        y += 4
        canvas.drawText(report.averagesNote(), margin, y, ink2)
        y += 22

        val columns = listOf("DATE" to 0f, "DAY" to 70f, "FEEDS" to 105f, "GAP" to 150f, "WET" to 200f, "DIRTY" to 240f, "STOOL" to 285f, "SLEEP" to 360f, "LONGEST" to 415f, "WEIGHT" to 475f)
        columns.forEach { (name, x) -> canvas.drawText(name, margin + x, y, ink2) }
        y += 6
        canvas.drawLine(margin, y, width - margin, y, rule)
        y += 13
        for (day in report.days) {
            newPageIfNeeded(16f)
            val paint = if (day.isComplete) ink else ink2
            val values = listOf(
                Format.monthDay(day.date, report.zone) + if (day.isComplete) "" else "*",
                day.dayOfLife?.toString() ?: "",
                day.feeds.toString(),
                if (day.longestFeedGapSeconds > 0) Format.compactDuration(day.longestFeedGapSeconds) else "",
                day.wet.toString(),
                day.dirty.toString(),
                day.stoolColors.joinToString(", ") { it.label.lowercase() }.take(14),
                if (day.sleepSeconds >= 60) Format.compactDuration(day.sleepSeconds) else "",
                if (day.longestSleepSeconds >= 60) Format.compactDuration(day.longestSleepSeconds) else "",
                day.weightGrams?.let { Format.grams(it, imperial) } ?: "",
            )
            values.zip(columns).forEach { (text, column) -> canvas.drawText(text, margin + column.second, y, paint) }
            y += 15
        }
        y += 4
        canvas.drawText("* Not in the averages: today so far, the day logging began, or a day with nothing logged.", margin, y, ink2)
        y += 13
        canvas.drawText("Gap: longest time between two logged feeds, start to start. Longest: longest single sleep. Only what was logged is counted.", margin, y, ink2)
        y += 22
        if (report.notes.isNotEmpty()) {
            newPageIfNeeded(30f)
            canvas.drawText("NOTES", margin, y, ink2)
            y += 15
            for ((date, text) in report.notes) {
                newPageIfNeeded(15f)
                canvas.drawText("${Format.monthDay(date, report.zone)} · $text".take(110), margin, y, ink)
                y += 14
            }
        }
        footer()
        doc.finishPage(page)
        val file = File(dir(context), "${safeName(report.childName).ifEmpty { "baby" }}-summary.pdf")
        file.outputStream().use(doc::writeTo)
        doc.close()
        return file
    }
}
