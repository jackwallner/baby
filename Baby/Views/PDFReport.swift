import CoreGraphics
import Foundation
import UIKit

/// The pediatrician summary, drawn as a PDF a parent can hand over or AirDrop
/// in the exam room.
///
/// Plain UIKit drawing rather than a SwiftUI snapshot: this has to paginate,
/// print at a real page size, and look the same in five years.
enum PDFReport {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter, 72 dpi
    private static let margin: CGFloat = 48

    private enum Font {
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let subtitle = UIFont.systemFont(ofSize: 11, weight: .regular)
        static let sectionLabel = UIFont.systemFont(ofSize: 9, weight: .semibold)
        static let statValue = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        static let statLabel = UIFont.systemFont(ofSize: 7.5, weight: .regular)
        static let columnHeader = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        static let cell = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        static let cellStrong = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        static let note = UIFont.systemFont(ofSize: 9.5, weight: .regular)
        static let footer = UIFont.systemFont(ofSize: 8, weight: .regular)
    }

    private enum Ink {
        static let primary = UIColor(white: 0.11, alpha: 1)
        static let secondary = UIColor(white: 0.42, alpha: 1)
        static let faint = UIColor(white: 0.72, alpha: 1)
        static let rule = UIColor(white: 0.85, alpha: 1)
        static let band = UIColor(white: 0.965, alpha: 1)
    }

    private struct Column: Sendable {
        let title: String
        var width: CGFloat
        let alignment: NSTextAlignment
        /// The button the column belongs to; nil for date, day and weight.
        var kind: EventKind? = nil
        let value: @Sendable (SummaryReport.Day) -> String
    }

    /// The widths add up to the 516pt content width exactly, and every cell is
    /// drawn 6pt narrower than its column so two numbers can never touch.
    private static let gutter: CGFloat = 6

    private static let allColumns: [Column] = [
        Column(title: "DATE", width: 52, alignment: .left) {
            // The asterisk marks a day the averages leave out; the key says why.
            $0.date.formatted(.dateTime.month(.abbreviated).day()) + ($0.isComplete ? "" : "*")
        },
        Column(title: "DAY", width: 24, alignment: .right) { $0.dayOfLife.map(String.init) ?? "" },
        Column(title: "FEEDS", width: 38, alignment: .right, kind: .feed) { String($0.feeds) },
        Column(title: "GAP", width: 52, alignment: .right, kind: .feed) {
            $0.longestFeedGapSeconds >= 60 ? Format.compactDuration($0.longestFeedGapSeconds) : ""
        },
        Column(title: "WET", width: 32, alignment: .right, kind: .wet) { String($0.wet) },
        Column(title: "DIRTY", width: 38, alignment: .right, kind: .dirty) { String($0.dirty) },
        Column(title: "BOTTLE", width: 44, alignment: .right, kind: .feed) {
            $0.bottleMillilitres > 0 ? Format.millilitres($0.bottleMillilitres) : ""
        },
        Column(title: "SLEEP", width: 56, alignment: .right, kind: .sleep) {
            $0.sleepSeconds >= 60 ? Format.compactDuration($0.sleepSeconds) : ""
        },
        Column(title: "LONGEST", width: 50, alignment: .right, kind: .sleep) {
            $0.longestSleepSeconds >= 60 ? Format.compactDuration($0.longestSleepSeconds) : ""
        },
        Column(title: "STOOL", width: 68, alignment: .left, kind: .dirty) {
            let colors = Array(Set($0.stoolColors.map(\.label))).sorted()
            return colors.joined(separator: ", ")
        },
        Column(title: "WEIGHT", width: 62, alignment: .right) {
            $0.weightGrams.map { Format.grams($0) } ?? ""
        },
    ]

    /// The columns for the buttons this family uses, widened in proportion
    /// so the table still spans the page.
    private static func columns(for tracked: TrackedKinds) -> [Column] {
        let kept = allColumns.filter { $0.kind.map(tracked.contains) ?? true }
        let total = kept.reduce(0) { $0 + $1.width }
        let full = allColumns.reduce(0) { $0 + $1.width }
        return kept.map { column in
            var column = column
            column.width *= full / total
            return column
        }
    }

    // MARK: - Rendering

    /// `isExample` stamps the page so a sample can never be mistaken for a
    /// record of the baby looking at it.
    static func render(_ report: SummaryReport, isExample: Bool = false) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: metadata(for: report))
        return renderer.pdfData { context in
            var rows = report.days[...]
            var page = 1
            repeat {
                context.beginPage()
                var y = margin
                if page == 1 {
                    y = drawHeader(report, isExample: isExample, at: y)
                    y = drawStats(report, at: y)
                }
                y = drawTableHeader(columns(for: report.tracked), at: y)
                while let day = rows.first, y + 18 < pageSize.height - margin - 40 {
                    drawRow(day, columns: columns(for: report.tracked), at: y, striped: (report.days.count - rows.count) % 2 == 1)
                    y += 18
                    rows = rows.dropFirst()
                }
                if rows.isEmpty {
                    y = drawKey(report, at: y + 8)
                    y = drawNotes(report, at: y + 12)
                }
                drawFooter(report, page: page, isExample: isExample)
                page += 1
            } while !rows.isEmpty
        }
    }

    static func url(for report: SummaryReport, isExample: Bool = false) throws -> URL {
        let data = render(report, isExample: isExample)
        let safeName = report.childName.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let name = "\(safeName.isEmpty ? "Baby" : safeName)-summary.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// First page as an image, for the on-screen preview. The preview is free;
    /// the file itself is what Baby+ unlocks.
    static func firstPageImage(_ data: Data, width: CGFloat, scale: CGFloat = 2, crop: CGRect? = nil) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        let bounds = page.getBoxRect(.mediaBox)
        // `crop` is in page points from the top left, so a pitch can show the
        // part of the page a parent reads first at a size they can read.
        let visible = crop ?? CGRect(origin: .zero, size: bounds.size)
        let ratio = width / visible.width
        let size = CGSize(width: width, height: visible.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: -visible.minX * ratio, y: (bounds.height - visible.minY) * ratio)
            context.cgContext.scaleBy(x: ratio, y: -ratio)
            context.cgContext.drawPDFPage(page)
        }
    }

    /// The name, the averages and the first rows: the paywall's preview card.
    static let previewCrop = CGRect(x: 36, y: 36, width: 540, height: 340)

    // MARK: - Pieces

    private static func metadata(for report: SummaryReport) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(report.childName): \(report.tracked.headline.lowercased())",
            kCGPDFContextCreator as String: "Baby Tracker",
        ]
        return format
    }

    private static func drawHeader(_ report: SummaryReport, isExample: Bool, at y: CGFloat) -> CGFloat {
        var y = y
        draw(report.childName, font: Font.title, color: Ink.primary, at: CGPoint(x: margin, y: y))
        if isExample {
            let badge = "EXAMPLE, NOT YOUR BABY'S DATA"
            let size = measure(badge, font: Font.sectionLabel)
            let rect = CGRect(x: pageSize.width - margin - size.width - 12, y: y + 4, width: size.width + 12, height: 16)
            UIColor(white: 0.92, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
            draw(badge, font: Font.sectionLabel, color: Ink.secondary, at: CGPoint(x: rect.minX + 6, y: rect.minY + 3.5))
        }
        y += 30
        var line = report.tracked.headline
        if let birth = report.birthDate {
            line += " · born \(birth.formatted(.dateTime.month(.abbreviated).day().year()))"
            if let day = DateHelpers.dayOfLife(birthDate: birth, on: report.end) {
                line += " · day \(day) on \(report.end.formatted(.dateTime.month(.abbreviated).day()))"
            }
        }
        draw(line, font: Font.subtitle, color: Ink.secondary, at: CGPoint(x: margin, y: y))
        y += 14
        draw("\(report.rangeLabel) · \(Format.count(report.dayCount, "day"))", font: Font.subtitle, color: Ink.secondary, at: CGPoint(x: margin, y: y))
        y += 22
        rule(at: y)
        return y + 18
    }

    /// One figure per button in use, each with the number a doctor asks about
    /// next, in rows of three so a detail line has room to be read.
    private static func drawStats(_ report: SummaryReport, at y: CGFloat) -> CGFloat {
        let stats = stats(for: report)
        let perRow = stats.count <= 4 ? stats.count : 3
        let width = (pageSize.width - margin * 2) / CGFloat(max(perRow, 1))
        let rowHeight: CGFloat = 44
        for (index, stat) in stats.enumerated() {
            let x = margin + CGFloat(index % perRow) * width
            let top = y + CGFloat(index / perRow) * rowHeight
            draw(stat.value, font: Font.statValue, color: Ink.primary,
                 at: CGPoint(x: x, y: top), width: width - gutter, alignment: .left)
            draw(stat.label.uppercased(), font: Font.statLabel, color: Ink.secondary,
                 at: CGPoint(x: x, y: top + 19), width: width - gutter, alignment: .left)
            if let detail = stat.detail {
                draw(detail, font: Font.statLabel, color: Ink.secondary,
                     at: CGPoint(x: x, y: top + 29), width: width - gutter, alignment: .left)
            }
        }
        var bottom = y + CGFloat((stats.count + perRow - 1) / max(perRow, 1)) * rowHeight
        draw(report.averagesNote, font: Font.footer, color: Ink.secondary, at: CGPoint(x: margin, y: bottom))
        bottom += 16
        rule(at: bottom)
        return bottom + 16
    }

    private struct Stat {
        let kind: EventKind
        let value: String
        let label: String
        var detail: String? = nil
    }

    private static func stats(for report: SummaryReport) -> [Stat] {
        let shortDate = Date.FormatStyle.dateTime.month(.abbreviated).day()
        var all: [Stat] = [
            Stat(kind: .feed, value: oneDecimal(report.averageFeedsPerDay), label: "feeds / day",
                 detail: report.longestFeedGapSeconds >= 60 ? "longest gap \(Format.compactDuration(report.longestFeedGapSeconds))" : nil),
        ]
        if report.averageBottleMillilitresPerDay > 0 {
            all.append(Stat(kind: .feed, value: Format.millilitres(report.averageBottleMillilitresPerDay), label: "bottle / day",
                            detail: "about \(Format.millilitres(report.averageBottleMillilitresPerFeed)) a bottle"))
        }
        all.append(Stat(kind: .wet, value: oneDecimal(report.averageWetPerDay), label: "wet / day",
                        detail: report.lowestDay(\.wet).map { "lowest day \($0.wet), \($0.date.formatted(shortDate))" }))
        all.append(Stat(kind: .dirty, value: oneDecimal(report.averageDirtyPerDay), label: "dirty / day",
                        detail: report.lowestDay(\.dirty).map { "lowest day \($0.dirty), \($0.date.formatted(shortDate))" }))
        all.append(Stat(kind: .sleep, value: report.averageSleepSeconds >= 60 ? Format.compactDuration(report.averageSleepSeconds) : "—", label: "sleep / day",
                        detail: report.longestSleepSeconds >= 60 ? "longest stretch \(Format.compactDuration(report.longestSleepSeconds))" : nil))
        all.append(Stat(kind: .weight, value: report.latestWeight.map { Format.grams($0) } ?? "—",
                        label: report.latestWeightDate.map { "weight, \($0.formatted(shortDate))" } ?? "weight",
                        detail: report.weightChangeDescription ?? "no weigh-ins in this range"))
        return all.filter { report.tracked.contains($0.kind) }
    }

    private static func drawTableHeader(_ columns: [Column], at y: CGFloat) -> CGFloat {
        var x = margin
        for column in columns {
            draw(column.title, font: Font.columnHeader, color: Ink.secondary,
                 at: CGPoint(x: x, y: y), width: column.width - gutter, alignment: column.alignment)
            x += column.width
        }
        rule(at: y + 13)
        return y + 19
    }

    private static func drawRow(_ day: SummaryReport.Day, columns: [Column], at y: CGFloat, striped: Bool) {
        if striped {
            Ink.band.setFill()
            UIBezierPath(rect: CGRect(x: margin - 4, y: y - 3, width: pageSize.width - margin * 2 + 8, height: 18)).fill()
        }
        var x = margin
        let empty = !day.hasEntries
        for (index, column) in columns.enumerated() {
            let value = column.value(day)
            let font = index <= 1 ? Font.cellStrong : Font.cell
            let color: UIColor = if empty && index > 1 || value.isEmpty {
                Ink.faint
            } else if !day.isComplete && index > 1 {
                // A partial day's numbers are real but incomplete: shown,
                // not weighed.
                Ink.secondary
            } else {
                Ink.primary
            }
            draw(value.isEmpty && index > 1 ? "·" : value,
                 font: font, color: color,
                 at: CGPoint(x: x, y: y), width: column.width - gutter, alignment: column.alignment)
            x += column.width
        }
    }

    private static func drawNotes(_ report: SummaryReport, at y: CGFloat) -> CGFloat {
        guard !report.notes.isEmpty else { return y }
        var y = y
        rule(at: y)
        y += 12
        draw("NOTES", font: Font.sectionLabel, color: Ink.secondary, at: CGPoint(x: margin, y: y))
        y += 14
        let width = pageSize.width - margin * 2
        let limit = pageSize.height - margin - 40
        for (index, note) in report.notes.enumerated() {
            let line = "\(note.date.formatted(.dateTime.month(.abbreviated).day())) · \(note.text)"
            let height = wrappedHeight(line, font: Font.note, width: width)
            guard y + height <= limit else {
                let rest = "\(report.notes.count - index) more in the app's History"
                draw(rest, font: Font.note, color: Ink.secondary, at: CGPoint(x: margin, y: y))
                return y + 13
            }
            drawWrapped(line, font: Font.note, color: Ink.primary, at: CGPoint(x: margin, y: y), width: width)
            y += height + 3
        }
        return y
    }

    private static func drawFooter(_ report: SummaryReport, page: Int, isExample: Bool) {
        let y = pageSize.height - margin - 16
        rule(at: y - 8)
        let left = isExample
            ? "Example page from Baby Tracker. The numbers are made up."
            : "Kept in Baby Tracker by the parent. A log of what was recorded, not medical advice."
        draw(left, font: Font.footer, color: Ink.secondary, at: CGPoint(x: margin, y: y))
        let right = "\(Date.now.formatted(.dateTime.month(.abbreviated).day().year())) · page \(page)"
        draw(right, font: Font.footer, color: Ink.secondary,
             at: CGPoint(x: margin, y: y), width: pageSize.width - margin * 2, alignment: .right)
    }

    /// What the columns a parent could misread mean, and what the asterisk is.
    private static func drawKey(_ report: SummaryReport, at y: CGFloat) -> CGFloat {
        let tracked = report.tracked
        var key: [String] = []
        if tracked.contains(.feed) { key.append("Gap: longest time between two logged feeds, start to start.") }
        if tracked.contains(.sleep) { key.append("Longest: longest single sleep.") }
        key.append("Only what was logged is counted.")
        var y = y
        draw(key.joined(separator: " "), font: Font.footer, color: Ink.secondary, at: CGPoint(x: margin, y: y))
        y += 12
        if report.days.contains(where: { !$0.isComplete }) {
            draw("* Not in the averages: today so far, the day logging began, or a day with nothing logged.",
                 font: Font.footer, color: Ink.secondary, at: CGPoint(x: margin, y: y))
            y += 12
        }
        return y
    }

    // MARK: - Drawing helpers

    private static func wrappedHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height)
    }

    private static func drawWrapped(_ text: String, font: UIFont, color: UIColor, at point: CGPoint, width: CGFloat) {
        let height = wrappedHeight(text, font: font, width: width)
        (text as NSString).draw(
            with: CGRect(x: point.x, y: point.y, width: width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .foregroundColor: color],
            context: nil
        )
    }

    private static func rule(at y: CGFloat) {
        Ink.rule.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: pageSize.width - margin * 2, height: 0.5)).fill()
    }

    private static func draw(
        _ text: String,
        font: UIFont,
        color: UIColor,
        at point: CGPoint,
        width: CGFloat? = nil,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]
        let size = CGSize(width: width ?? (pageSize.width - point.x - margin), height: font.lineHeight + 2)
        text.draw(in: CGRect(origin: point, size: size), withAttributes: attributes)
    }

    private static func measure(_ text: String, font: UIFont) -> CGSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private static func oneDecimal(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f", value) : "—"
    }
}
