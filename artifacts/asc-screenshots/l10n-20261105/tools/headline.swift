import AppKit
import CoreText
import Foundation

struct Job: Decodable {
    let text: String
    let locale: String
    let font: String
    let color: [Double]
    let box: [Int]
    let size: Double?
    let maxSize: Double?
    let minSize: Double?
    let align: String?
    let out: String?
}
struct Result: Encodable {
    let size: Double
    let width: Double
    let height: Double
    let fits: Bool
    let font: String
}
struct Layout {
    let lines: [CTLine]
    let bounds: [CGRect]
    let width: CGFloat
    let height: CGFloat
    let gap: CGFloat
}
enum Failure: Error { case invalid(String) }

func covers(_ font: NSFont, _ text: String) -> Bool {
    let characters = CTFontCopyCharacterSet(font)
    return text.unicodeScalars.allSatisfy {
        CharacterSet.whitespacesAndNewlines.contains($0) ||
        [0x200C, 0x200D, 0x200E, 0x200F, 0xFE0E, 0xFE0F].contains($0.value) ||
        CFCharacterSetIsLongCharacterMember(characters, $0.value)
    }
}

func chooseFont(_ job: Job) -> NSFont {
    let locale = job.locale.replacingOccurrences(of: "_", with: "-").lowercased()
    var names = [job.font]
    if locale.hasPrefix("ja") { names += ["HiraginoSans-W8"] }
    if locale.hasPrefix("zh") {
        names += locale.contains("hant") || locale.contains("tw") || locale.contains("hk")
            ? ["PingFangTC-Semibold"] : ["PingFangSC-Semibold"]
    }
    if locale.hasPrefix("ko") { names += ["AppleSDGothicNeo-Heavy"] }
    if locale.hasPrefix("th") { names += ["SukhumvitSet-Bold", "Thonburi-Bold"] }
    if locale.hasPrefix("hi") { names += ["KohinoorDevanagari-Bold"] }
    if locale.hasPrefix("ar") { names += ["AlNile-Bold", "GeezaPro-Bold"] }
    if locale.hasPrefix("he") { names += ["ArialHebrew-Bold"] }
    if job.text.unicodeScalars.contains(where: { (0x370...0x52F).contains($0.value) }) {
        names += ["HelveticaNeue-CondensedBold", "HelveticaNeue-Bold"]
    }
    for name in names {
        if let font = NSFont(name: name, size: 100), covers(font, job.text) { return font }
    }
    return NSFont.systemFont(ofSize: 100, weight: .bold)
}

func layout(_ job: Job, _ font: NSFont, _ size: CGFloat) -> Layout {
    let sized = CTFontCreateCopyWithAttributes(font, size, nil, nil)
    let c = job.color
    let color = NSColor(srgbRed: c[0] / 255, green: c[1] / 255, blue: c[2] / 255, alpha: 1)
    let rtl = ["ar", "he", "fa", "ur"].contains(String(job.locale.prefix(2)))
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
    let lines = job.text.components(separatedBy: "\n").map { text -> CTLine in
        let value = NSAttributedString(string: text, attributes: [
            .font: sized, .foregroundColor: color, .paragraphStyle: paragraph,
            .languageIdentifier: job.locale,
        ])
        return CTLineCreateWithAttributedString(value)
    }
    let bounds = lines.map { line -> CGRect in
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        return ink.isNull ? .zero : ink
    }
    // Actual glyph bounds include stacked marks. Ink bands always have a clear gap.
    let gap = max(4, size * 0.13)
    let height = bounds.reduce(CGFloat(0)) { $0 + ceil($1.height) } + gap * CGFloat(max(0, lines.count - 1))
    return Layout(lines: lines, bounds: bounds, width: bounds.map { $0.width }.max() ?? 0,
                  height: height, gap: gap)
}

func render(_ job: Job) throws -> Result {
    guard job.box.count == 2, job.box.allSatisfy({ $0 > 0 && $0 <= 20000 }),
          job.color.count == 3, job.color.allSatisfy({ $0 >= 0 && $0 <= 255 }),
          ["left", "center"].contains(job.align ?? "center") else {
        throw Failure.invalid("invalid box, color or alignment")
    }
    let font = chooseFont(job)
    let minSize = job.minSize ?? 1, maxSize = job.maxSize ?? 200
    guard minSize > 0, maxSize >= minSize, (job.size ?? 1) > 0 else {
        throw Failure.invalid("invalid font size range")
    }
    func fits(_ size: Double) -> Bool {
        let value = layout(job, font, CGFloat(size))
        return value.width <= CGFloat(job.box[0] - 4) && value.height <= CGFloat(job.box[1] - 6)
    }
    var size = job.size ?? minSize
    if job.size == nil {
        var low = minSize, high = maxSize
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        size = fits(maxSize) ? maxSize : floor(low * 4) / 4
        size = max(minSize, size)
    }
    let value = layout(job, font, CGFloat(size))
    if let path = job.out {
        let width = job.box[0], height = job.box[1]
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
            throw Failure.invalid("cannot allocate bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let ctx = graphics.cgContext
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.textMatrix = .identity
        let rtl = ["ar", "he", "fa", "ur"].contains(String(job.locale.prefix(2)))
        var top = (CGFloat(height) - value.height) / 2
        for (line, bounds) in zip(value.lines, value.bounds) {
            var x: CGFloat = 1
            if job.align ?? "center" == "center" { x = (CGFloat(width) - bounds.width) / 2 }
            else if rtl { x = CGFloat(width) - bounds.width - 1 }
            ctx.textPosition = CGPoint(x: x - bounds.minX, y: CGFloat(height) - top - bounds.maxY)
            CTLineDraw(line, ctx)
            top += ceil(bounds.height) + value.gap
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Failure.invalid("cannot encode PNG")
        }
        try data.write(to: URL(fileURLWithPath: path))
    }
    return Result(size: size, width: Double(value.width), height: Double(value.height),
                  fits: fits(size), font: font.fontName)
}

do {
    let jobs = try JSONDecoder().decode([Job].self, from: FileHandle.standardInput.readDataToEndOfFile())
    let results = try jobs.map(render)
    print(String(data: try JSONEncoder().encode(results), encoding: .utf8)!)
} catch {
    FileHandle.standardError.write(Data("headline: \(error)\n".utf8))
    exit(1)
}
