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
        let width: CGFloat
        let alignment: NSTextAlignment
        let value: @Sendable (SummaryReport.Day) -> String
    }

    /// The widths add up to the 516pt content width exactly, and every cell is
    /// drawn 6pt narrower than its column so two numbers can never touch.
    private static let gutter: CGFloat = 6

    private static let columns: [Column] = [
        Column(title: "DATE", width: 76, alignment: .left) {
            $0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        },
        Column(title: "DAY", width: 30, alignment: .right) { $0.dayOfLife.map(String.init) ?? "" },
        Column(title: "FEEDS", width: 42, alignment: .right) { String($0.feeds) },
        Column(title: "WET", width: 36, alignment: .right) { String($0.wet) },
        Column(title: "DIRTY", width: 40, alignment: .right) { String($0.dirty) },
        Column(title: "BOTTLE", width: 50, alignment: .right) {
            $0.bottleMillilitres > 0 ? "\(Int($0.bottleMillilitres)) ml" : ""
        },
        Column(title: "SLEEP", width: 50, alignment: .right) {
            $0.sleepSeconds >= 60 ? Format.compactDuration($0.sleepSeconds) : ""
        },
        Column(title: "LONGEST", width: 54, alignment: .right) {
            $0.longestSleepSeconds >= 60 ? Format.compactDuration($0.longestSleepSeconds) : ""
        },
        Column(title: "STOOL", width: 88, alignment: .left) {
            let colors = Array(Set($0.stoolColors.map(\.label))).sorted()
            return colors.joined(separator: ", ")
        },
        Column(title: "WEIGHT", width: 50, alignment: .right) {
            $0.weightGrams.map { Format.grams($0) } ?? ""
        },
    ]

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
                y = drawTableHeader(at: y)
                while let day = rows.first, y + 18 < pageSize.height - margin - 40 {
                    drawRow(day, at: y, striped: (report.days.count - rows.count) % 2 == 1)
                    y += 18
                    rows = rows.dropFirst()
                }
                if rows.isEmpty {
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
    static func firstPageImage(_ data: Data, width: CGFloat, scale: CGFloat = 2) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        let bounds = page.getBoxRect(.mediaBox)
        let ratio = width / bounds.width
        let size = CGSize(width: width, height: bounds.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: ratio, y: -ratio)
            context.cgContext.drawPDFPage(page)
        }
    }

    // MARK: - Pieces

    private static func metadata(for report: SummaryReport) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(report.childName): feeds, diapers and sleep",
            kCGPDFContextCreator as String: "Baby Tracker",
        ]
        return format
    }

    private static func drawHeader(_ report: SummaryReport, isExample: Bool, at y: CGFloat) -> CGFloat {
        var y = y
        draw("Feeds, diapers and sleep", font: Font.title, color: Ink.primary, at: CGPoint(x: margin, y: y))
        if isExample {
            let badge = "EXAMPLE, NOT YOUR BABY'S DATA"
            let size = measure(badge, font: Font.sectionLabel)
            let rect = CGRect(x: pageSize.width - margin - size.width - 12, y: y + 4, width: size.width + 12, height: 16)
            UIColor(white: 0.92, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
            draw(badge, font: Font.sectionLabel, color: Ink.secondary, at: CGPoint(x: rect.minX + 6, y: rect.minY + 3.5))
        }
        y += 30
        var line = report.childName
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

    private static func drawStats(_ report: SummaryReport, at y: CGFloat) -> CGFloat {
        let stats: [(String, String)] = [
            (oneDecimal(report.averageFeedsPerDay), "feeds / day"),
            (oneDecimal(report.averageWetPerDay), "wet / day"),
            (oneDecimal(report.averageDirtyPerDay), "dirty / day"),
            (report.averageSleepSeconds >= 60 ? Format.compactDuration(report.averageSleepSeconds) : "—", "sleep / day"),
            (report.longestSleepSeconds >= 60 ? Format.compactDuration(report.longestSleepSeconds) : "—", "longest"),
            (weightValue(report), weightLabel(report)),
        ]
        let width = (pageSize.width - margin * 2) / CGFloat(stats.count)
        for (index, stat) in stats.enumerated() {
            let x = margin + CGFloat(index) * width
            draw(stat.0, font: Font.statValue, color: Ink.primary,
                 at: CGPoint(x: x, y: y), width: width - gutter, alignment: .left)
            draw(stat.1.uppercased(), font: Font.statLabel, color: Ink.secondary,
                 at: CGPoint(x: x, y: y + 19), width: width - gutter, alignment: .left)
        }
        let bottom = y + 40
        rule(at: bottom)
        return bottom + 16
    }

    private static func weightValue(_ report: SummaryReport) -> String {
        report.latestWeight.map { Format.grams($0) } ?? "—"
    }

    /// The change rides in the label rather than the value, which is how a
    /// six-tile row stays legible at 86 points each.
    private static func weightLabel(_ report: SummaryReport) -> String {
        guard let change = report.weightChangeGrams else { return "weight" }
        let sign = change > 0 ? "+" : "−"
        return "weight \(sign)\(Int(abs(change)))g"
    }

    private static func drawTableHeader(at y: CGFloat) -> CGFloat {
        var x = margin
        for column in columns {
            draw(column.title, font: Font.columnHeader, color: Ink.secondary,
                 at: CGPoint(x: x, y: y), width: column.width - gutter, alignment: column.alignment)
            x += column.width
        }
        rule(at: y + 13)
        return y + 19
    }

    private static func drawRow(_ day: SummaryReport.Day, at y: CGFloat, striped: Bool) {
        if striped {
            Ink.band.setFill()
            UIBezierPath(rect: CGRect(x: margin - 4, y: y - 3, width: pageSize.width - margin * 2 + 8, height: 18)).fill()
        }
        var x = margin
        let empty = day.feeds == 0 && day.wet == 0 && day.dirty == 0 && day.sleepSeconds == 0
        for (index, column) in columns.enumerated() {
            let value = column.value(day)
            let font = index <= 1 ? Font.cellStrong : Font.cell
            draw(value.isEmpty && index > 1 ? "·" : value,
                 font: font,
                 color: empty && index > 1 ? Ink.faint : (value.isEmpty ? Ink.faint : Ink.primary),
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
        for note in report.notes.prefix(8) {
            let line = "\(note.date.formatted(.dateTime.month(.abbreviated).day())) · \(note.text)"
            draw(line, font: Font.note, color: Ink.primary, at: CGPoint(x: margin, y: y), width: pageSize.width - margin * 2, alignment: .left)
            y += 13
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

    // MARK: - Drawing helpers

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
