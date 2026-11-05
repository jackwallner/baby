// FleetQA: release-gate oracles for XCUITest journeys.
//
// Vendored into each app's UI test target by `qa-gate install`. Edit the
// source in ~/ios/qa/FleetQA/FleetQA.swift and reinstall; a local edit to a
// vendored copy is overwritten and flagged by `qa-gate run`.
//
// The journeys class is `@MainActor`, like FleetQA. A journey calls `QA.launch(app)` and then `QA.checkpoint(app, "name")` after
// every step a user would see. Each checkpoint runs every oracle, so a journey
// author never has to remember to assert "nothing is clipped, nothing moves
// late, no em dash, no NaN". Findings go to QA_OUTPUT_DIR as JSON lines; the
// qa-gate runner applies the app's ledger and decides the verdict. Checkpoints
// never fail the test themselves (set QA_STRICT=1 to fail on P0/P1), so one
// run collects every finding instead of stopping at the first.

import UIKit
import Vision
import XCTest

@MainActor
enum QA {
    static let env = ProcessInfo.processInfo.environment
    static let persona = env["QA_PERSONA"] ?? "local"
    static let outputDir: URL? = env["QA_OUTPUT_DIR"].map { URL(fileURLWithPath: $0) }
    static let strict = env["QA_STRICT"] == "1"
    /// Findings of the most recent checkpoint, for FleetQA's own tests.
    static var lastFindings: [(oracle: String, severity: String, detail: String)] = []

    /// Applies the persona's launch arguments and environment, then launches.
    static func launch(_ app: XCUIApplication, environment: [String: String] = [:], arguments: [String] = [],
                       journey: String = #function) {
        app.launchArguments += arguments + (decode([String].self, env["QA_LAUNCH_ARGUMENTS"]) ?? [])
        for (key, value) in environment { app.launchEnvironment[key] = value }
        for (key, value) in decode([String: String].self, env["QA_LAUNCH_ENVIRONMENT"]) ?? [:] {
            app.launchEnvironment[key] = value
        }
        system("launch", journey: journey) { app.launch() }
    }

    /// Marks a span the OS animates (launch, home, relaunch) so the runner does
    /// not blame the app for springboard motion recorded on the video.
    static func system(_ kind: String, journey: String, _ action: () -> Void) {
        let start = Date().timeIntervalSince1970
        action()
        write("system.jsonl", ["kind": kind, "journey": journey.replacingOccurrences(of: "()", with: ""),
                               "start": start, "end": Date().timeIntervalSince1970])
    }

    /// Runs every oracle against the screen as the user now sees it.
    ///
    /// - Parameters:
    ///   - ambient: element labels or identifiers that animate on purpose while
    ///     the screen is idle (a breathing circle, a live timer). They are left
    ///     out of the layout-shift and idle oracles.
    ///   - grace: seconds after the step during which movement is the step's
    ///     own transition. Movement after it is a late layout shift.
    ///   - paywall: run the paywall oracles. `nil` decides from the checkpoint
    ///     name (paywall, upgrade, trial, pitch, offer, plans, subscribe) or
    ///     from the screen (a price next to a Restore control).
    static func checkpoint(_ app: XCUIApplication, _ name: String, ambient: [String] = [], grace: TimeInterval = 0.8,
                           observe: TimeInterval = 5, paywall: Bool? = nil, journey: String = #function,
                           file: StaticString = #filePath, line: UInt = #line) {
        let context = Context(journey: journey.replacingOccurrences(of: "()", with: ""), checkpoint: name)
        XCTContext.runActivity(named: "QA checkpoint \(name)") { _ in
            let started = Date()
            if app.state != .runningForeground { _ = app.wait(for: .runningForeground, timeout: 5) }
            guard app.state == .runningForeground else {
                // Show whatever took the screen: a crash leaves the home screen, an alert stays on top.
                _ = save(capture(nil), context)
                record(context, "crash", "P0", "", app.state == .notRunning
                       ? "the app is not running at this checkpoint (crashed or was killed)"
                       : "the app is in the background at this checkpoint (state \(app.state.rawValue)); see the screenshot for what took the screen")
                lastFindings = context.findings
                if strict { XCTFail("[crash] \(name): app left the foreground", file: file, line: line) }
                return
            }
            let settle = Layout.settle(app, grace: grace, ambient: Set(ambient), context: context)
            let shot = capture(app)
            let shotPath = save(shot, context)
            let leaves = settle.final
            Layout.offscreen(leaves, width: settle.width, context: context)
            let rendered = Render.read(shot)
            Render.truncation(leaves, rendered, context: context)
            Render.clipped(leaves, rendered, context: context)
            Layout.overlaps(app, leaves, rendered, context: context)
            Copy.lint(leaves, context: context)
            States.check(leaves, rendered, height: settle.height, context: context)
            Anchor.check(app, leaves, width: settle.width, height: settle.height, context: context)
            if paywall ?? Paywall.looksLike(app, name: name, leaves: leaves) {
                Paywall.check(app, leaves, rendered, context: context)
            }
            // Apple's audit re-renders the app at other text sizes; its motion is not the app's.
            system("audit", journey: context.journey) { Audit.run(app, shot: shot, leaves: leaves, context: context) }
            Idle.check(app, first: shot, ambient: leaves.filter { ambient.contains($0.label) || ambient.contains($0.identifier) },
                       context: context)
            // Data that lands a few seconds late still jumps under the user's eye, so
            // every screen is watched for at least `observe` seconds before the recheck.
            let watched = Date().timeIntervalSince(started)
            if watched < observe { usleep(UInt32((observe - watched) * 1_000_000)) }
            Layout.recheck(app, settled: leaves, ambient: Set(ambient), seconds: Date().timeIntervalSince(started),
                           context: context)
            States.spinner(app, seconds: Date().timeIntervalSince(started), context: context)
            write("checkpoints.jsonl", [
                "persona": persona, "journey": context.journey, "checkpoint": name,
                "started": started.timeIntervalSince1970, "finished": Date().timeIntervalSince1970,
                "settle_ms": Int(settle.settleSeconds * 1000), "settled": settle.settled,
                "samples": settle.samples, "elements": leaves.count, "screenshot": shotPath ?? "",
            ])
            lastFindings = context.findings
            if strict {
                for finding in context.findings where finding.severity == "P0" || finding.severity == "P1" {
                    XCTFail("[\(finding.oracle)] \(name): \(finding.detail)", file: file, line: line)
                }
            }
        }
    }

    /// Sends the app to the background and back, the commonest interruption.
    static func interrupt(_ app: XCUIApplication, seconds: UInt32 = 2, journey: String = #function) {
        system("interrupt", journey: journey) {
            XCUIDevice.shared.press(.home)
            sleep(seconds)
            app.activate()
            _ = app.wait(for: .runningForeground, timeout: 15)
            sleep(1)  // the springboard zoom outlasts the state change
        }
    }

    enum Direction { case left, right, up, down }

    /// A swipe across the element (`.up` scrolls content up, like `swipeUp()`).
    /// XCTest's own swipes land rotated on an unfolded iPhone Duo, whose inner
    /// display is turned against the device; a drag between element
    /// coordinates works on every device.
    static func swipe(_ element: XCUIElement, _ direction: Direction = .left) {
        let (from, to): (CGVector, CGVector) = switch direction {
        case .left: (CGVector(dx: 0.85, dy: 0.5), CGVector(dx: 0.1, dy: 0.5))
        case .right: (CGVector(dx: 0.15, dy: 0.5), CGVector(dx: 0.9, dy: 0.5))
        case .up: (CGVector(dx: 0.5, dy: 0.8), CGVector(dx: 0.5, dy: 0.25))
        case .down: (CGVector(dx: 0.5, dy: 0.25), CGVector(dx: 0.5, dy: 0.8))
        }
        element.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.05, thenDragTo: element.coordinate(withNormalizedOffset: to),
                   withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// Kills and relaunches without reinstalling: state must survive this.
    static func relaunch(_ app: XCUIApplication, journey: String = #function) {
        system("relaunch", journey: journey) {
            app.terminate()
            app.launch()
        }
    }

    // MARK: - Findings

        final class Context {
        let journey: String
        let checkpoint: String
        var findings: [(oracle: String, severity: String, detail: String)] = []
        init(journey: String, checkpoint: String) {
            self.journey = journey
            self.checkpoint = checkpoint
        }
    }

    static func record(_ context: Context, _ oracle: String, _ severity: String, _ element: String, _ detail: String,
                       extra: [String: Any] = [:]) {
        context.findings.append((oracle, severity, detail))
        var row: [String: Any] = [
            "persona": persona, "journey": context.journey, "checkpoint": context.checkpoint,
            "oracle": oracle, "severity": severity, "element": element, "detail": detail,
            "at": Date().timeIntervalSince1970,
        ]
        row.merge(extra) { _, new in new }
        write("findings.jsonl", row)
        XCTContext.runActivity(named: "QA \(severity) [\(oracle)] \(detail)") { _ in }
    }

    static func write(_ file: String, _ row: [String: Any]) {
        guard let dir = outputDir, let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(file)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data + Data([0x0A]))
            try? handle.close()
        } else {
            try? (data + Data([0x0A])).write(to: url)
        }
    }

    /// What is on screen, upright. An unfolded iPhone Duo draws the app on its
    /// inner display, which is not `XCUIScreen.main` (that shot is black), and
    /// the inner display's capture comes rotated, so it is redrawn upright to
    /// match the element frames the oracles compare it with.
    static func capture(_ app: XCUIApplication?) -> UIImage {
        let image: UIImage
        if let inner = XCUIScreen.screens.first(where: { $0 != XCUIScreen.main }) {
            image = inner.screenshot().image
        } else {
            image = app?.screenshot().image ?? XCUIScreen.main.screenshot().image
        }
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func save(_ shot: UIImage, _ context: Context) -> String? {
        let attachment = XCTAttachment(image: shot)
        attachment.name = "\(context.journey)-\(context.checkpoint)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "screenshot \(context.checkpoint)") { $0.add(attachment) }
        guard let dir = outputDir?.appendingPathComponent("shots") else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(slug("\(persona)-\(context.journey)-\(context.checkpoint)") + ".png")
        return (try? shot.pngData()?.write(to: url)) == nil ? nil : url.path
    }

    static func slug(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    static func decode<T: Decodable>(_ type: T.Type, _ text: String?) -> T? {
        guard let data = text?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Layout: late shifts, off-screen, overlaps

struct Leaf {
    let key: String
    let type: XCUIElement.ElementType
    let label: String
    let identifier: String
    let frame: CGRect
    let inScroll: Bool

    var name: String { identifier.isEmpty ? label : identifier }
}

@MainActor
enum Layout {
    static let textual: Set<XCUIElement.ElementType> = [.staticText, .button, .textField, .secureTextField, .switch, .link]
    static let scrolling: Set<XCUIElement.ElementType> = [.scrollView, .collectionView, .table, .webView]

    struct Result {
        var final: [Leaf]
        var width: CGFloat
        var height: CGFloat
        var settled: Bool
        var settleSeconds: TimeInterval
        var samples: Int
    }

    /// Visible leaves of the accessibility tree, keyed so the same element can
    /// be followed from one sample to the next.
    static func leaves(_ app: XCUIApplication) -> (leaves: [Leaf], width: CGFloat, height: CGFloat)? {
        guard let root = try? app.snapshot() else { return nil }
        let window = root.children.first { $0.elementType == .window }?.frame ?? root.frame
        var seen: [String: Int] = [:]
        var out: [Leaf] = []
        func walk(_ node: XCUIElementSnapshot, inScroll: Bool) {
            let scroll = inScroll || scrolling.contains(node.elementType)
            if node.children.isEmpty || node.elementType == .button || node.elementType == .switch {
                let frame = node.frame
                let label = node.label
                if frame.width > 0.5, frame.height > 0.5, frame.intersects(window),
                   !(node.elementType == .other && label.isEmpty) {
                    let base = "\(node.elementType.rawValue)|\(node.identifier.isEmpty ? label : node.identifier)"
                    let n = seen[base, default: 0]
                    seen[base] = n + 1
                    out.append(Leaf(key: "\(base)#\(n)", type: node.elementType, label: label,
                                    identifier: node.identifier, frame: frame, inScroll: scroll))
                }
                return
            }
            for child in node.children { walk(child, inScroll: scroll) }
        }
        walk(root, inScroll: false)
        return (out, window.width, window.height)
    }

    /// Samples the tree until it holds still, and scores movement after the
    /// grace period the way the web scores Cumulative Layout Shift: an element
    /// already on screen that moves or resizes is a late shift, weighted by how
    /// much of the screen it covers and how far it went.
    static func settle(_ app: XCUIApplication, grace: TimeInterval, ambient: Set<String>, context: QA.Context,
                       hold: TimeInterval = 0.9, timeout: TimeInterval = 8) -> Result {
        let start = Date()
        var previous: (time: TimeInterval, leaves: [String: Leaf])?
        var stableSince: TimeInterval?
        var last: [Leaf] = []
        var width: CGFloat = 1, height: CGFloat = 1
        var samples = 0
        var shifts: [String: (score: Double, detail: String, label: String)] = [:]
        while true {
            let now = Date().timeIntervalSince(start)
            guard let sample = leaves(app) else { break }
            samples += 1
            last = sample.leaves
            width = max(sample.width, 1)
            height = max(sample.height, 1)
            let current = Dictionary(sample.leaves.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            var moved = false
            if let prior = previous {
                for (key, leaf) in current {
                    guard let before = prior.leaves[key], !ambient.contains(leaf.label), !ambient.contains(leaf.identifier) else { continue }
                    let dx = abs(leaf.frame.minX - before.frame.minX), dy = abs(leaf.frame.minY - before.frame.minY)
                    let dw = abs(leaf.frame.width - before.frame.width), dh = abs(leaf.frame.height - before.frame.height)
                    guard max(dx, dy, dw, dh) > 1 else { continue }
                    moved = true
                    // Scrolling moves everything inside a scroll view together;
                    // the journey scrolled on purpose, so only resizes count there.
                    if prior.time < grace || (leaf.inScroll && dw <= 1 && dh <= 1 && allMovedTogether(prior.leaves, current)) { continue }
                    let union = leaf.frame.union(before.frame)
                    let impact = Double(union.width * union.height / (width * height))
                    let distance = Double(max(dx, dy, dw, dh) / max(width, height))
                    let score = min(impact, 1) * min(distance, 1)
                    let detail = String(format: "%@ \"%@\" %@ %.0fpt at +%.1fs after the step settled",
                                        typeName(leaf.type), leaf.name, dw > 1 || dh > 1 ? "resized" : "moved",
                                        max(dx, dy, dw, dh), now)
                    let worst = shifts[key]
                    shifts[key] = (score: (worst?.score ?? 0) + score, detail: worst?.detail ?? detail, label: leaf.name)
                }
                if current.count != prior.leaves.count { moved = true }
            }
            if moved || previous == nil { stableSince = now }
            previous = (now, current)
            if let since = stableSince, now - since >= hold, now >= grace { break }
            if now > timeout {
                QA.record(context, "never-settles", "P2", "", String(format: "layout still changing %.0fs after the step", timeout))
                break
            }
            usleep(120_000)
        }
        let total = shifts.values.reduce(0) { $0 + $1.score }
        if total >= 0.02, let worst = shifts.values.max(by: { $0.score < $1.score }) {
            let severity = total >= 0.1 ? "P1" : "P2"
            QA.record(context, "layout-shift", severity, worst.label,
                      String(format: "late layout shift %.3f (web CLS scale, 0.1 is poor): %@; %d element(s) moved",
                             total, worst.detail, shifts.count),
                      extra: ["score": total, "elements": shifts.values.map(\.label)])
        }
        let elapsed = Date().timeIntervalSince(start)
        return Result(final: last, width: width, height: height, settled: elapsed <= timeout,
                      settleSeconds: max(0, (stableSince ?? elapsed)), samples: samples)
    }

    /// Samples once more after the slower oracles ran. The screen looked settled
    /// before them; anything that moved since arrived late (data that loaded after
    /// the first frame, a card inserted on a timer) and the user saw it jump.
    static func recheck(_ app: XCUIApplication, settled: [Leaf], ambient: Set<String>, seconds: TimeInterval,
                        context: QA.Context) {
        guard let sample = leaves(app) else { return }
        let width = max(sample.width, 1), height = max(sample.height, 1)
        let before = Dictionary(settled.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(sample.leaves.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        if allMovedTogether(before, after) { return }
        var total = 0.0
        var moved: [String] = []
        var worst = (score: 0.0, detail: "", label: "")
        for (key, leaf) in after {
            guard let old = before[key], !ambient.contains(leaf.label), !ambient.contains(leaf.identifier) else { continue }
            let dx = abs(leaf.frame.minX - old.frame.minX), dy = abs(leaf.frame.minY - old.frame.minY)
            let dw = abs(leaf.frame.width - old.frame.width), dh = abs(leaf.frame.height - old.frame.height)
            let distance = max(dx, dy, dw, dh)
            guard distance > 1 else { continue }
            let union = leaf.frame.union(old.frame)
            let score = min(Double(union.width * union.height / (width * height)), 1) * min(Double(distance / max(width, height)), 1)
            total += score
            moved.append(leaf.name)
            if score > worst.score {
                worst = (score, String(format: "%@ \"%@\" %@ %.0fpt within %.1fs of the screen looking settled",
                                       typeName(leaf.type), leaf.name, dw > 1 || dh > 1 ? "resized" : "moved", distance,
                                       seconds), leaf.name)
            }
        }
        guard total >= 0.02 else { return }
        QA.record(context, "layout-shift", total >= 0.1 ? "P1" : "P2", worst.label,
                  String(format: "late layout shift %.3f (web CLS scale, 0.1 is poor): %@; %d element(s) moved",
                         total, worst.detail, moved.count),
                  extra: ["score": total, "elements": moved])
    }

    static func allMovedTogether(_ before: [String: Leaf], _ after: [String: Leaf]) -> Bool {
        let deltas = after.compactMap { key, leaf -> CGFloat? in
            guard leaf.inScroll, let old = before[key] else { return nil }
            return (leaf.frame.minY - old.frame.minY).rounded()
        }
        guard let first = deltas.first else { return false }
        return deltas.filter { abs($0 - first) <= 1 }.count * 10 >= deltas.count * 8
    }

    /// Anything cut by the left or right screen edge outside a scroll view.
    static func offscreen(_ leaves: [Leaf], width: CGFloat, context: QA.Context) {
        for leaf in leaves where !leaf.inScroll && textual.contains(leaf.type) {
            let cut = max(0, -leaf.frame.minX) + max(0, leaf.frame.maxX - width)
            guard cut > 2 else { continue }
            QA.record(context, "offscreen", "P1", leaf.name,
                      String(format: "%@ \"%@\" runs %.0fpt past the screen edge (x %.0f to %.0f, screen %.0f)",
                             typeName(leaf.type), leaf.name, cut, leaf.frame.minX, leaf.frame.maxX, width))
        }
    }

    /// Two texts, or two buttons, drawn over each other.
    static func overlaps(_ app: XCUIApplication, _ leaves: [Leaf], _ rendered: [Render.Line], context: QA.Context) {
        let candidates = leaves.filter { $0.type == .staticText || $0.type == .button }
        var reported = Set<String>()
        for (i, a) in candidates.enumerated() {
            for b in candidates[(i + 1)...] where a.type == b.type {
                let overlap = a.frame.intersection(b.frame)
                guard !overlap.isNull, overlap.width > 2, overlap.height > 2 else { continue }
                if a.frame.contains(b.frame) || b.frame.contains(a.frame) { continue }
                let smaller = min(a.frame.width * a.frame.height, b.frame.width * b.frame.height)
                guard overlap.width * overlap.height > 0.2 * smaller else { continue }
                let pair = [a.name, b.name].sorted().joined(separator: " / ")
                guard !reported.contains(pair) else { continue }
                // TabView keeps every tab in the accessibility tree at full size;
                // only a pair the user can actually see is an overlap.
                // Both must actually be drawn there (TabView keeps hidden tabs in the
                // tree and even reports them hittable), and the text must read badly:
                // two labels whose frames touch but that both read cleanly are padding.
                // Text stacked on text often reads as one garbled line ("BOSSTVADELPARAPICK"),
                // so neither label is found: that counts too, when something is drawn in
                // the overlap that no cleanly read element accounts for.
                let readA = Render.presence(a, rendered), readB = Render.presence(b, rendered)
                // Partly drawn counts only the words each label does not share with the
                // other, or a line covered by a card reads as drawn through the card's own words.
                let ownA = Render.presence(a, rendered, excluding: b.label)
                let ownB = Render.presence(b, rendered, excluding: a.label)
                let partly = ownA >= 0.3 && ownB >= 0.3 && min(readA, readB) < 0.9
                let garbled = max(readA, readB) < 0.9 && Render.unexplained(in: overlap, rendered, leaves: leaves)
                guard partly || garbled, visible(app, a), visible(app, b) else { continue }
                reported.insert(pair)
                QA.record(context, "overlap", "P1", pair,
                          String(format: "%@ \"%@\" overlaps \"%@\" by %.0f%%", typeName(a.type), a.name, b.name,
                                 100 * overlap.width * overlap.height / smaller))
            }
        }
    }

    /// Resolves a snapshot leaf back to a live element and asks whether a tap
    /// would reach it: false for hidden tabs, covered views and clipped scroll content.
    static func visible(_ app: XCUIApplication, _ leaf: Leaf) -> Bool {
        let parts = leaf.key.split(separator: "#")
        let index = Int(parts.last ?? "0") ?? 0
        let query = leaf.identifier.isEmpty
            ? app.descendants(matching: leaf.type).matching(NSPredicate(format: "label == %@", leaf.label))
            : app.descendants(matching: leaf.type).matching(identifier: leaf.identifier)
        // The same label can sit inside a button the leaf walk stops at (a list row
        // repeating a card's line), so the index alone can name the wrong copy.
        let near = { (frame: CGRect) in
            abs(frame.minX - leaf.frame.minX) < 1 && abs(frame.minY - leaf.frame.minY) < 1
                && abs(frame.width - leaf.frame.width) < 1 && abs(frame.height - leaf.frame.height) < 1
        }
        let element = query.allElementsBoundByIndex.first { near($0.frame) } ?? query.element(boundBy: index)
        return element.exists && element.isHittable
    }

    static func typeName(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .staticText: return "text"
        case .button: return "button"
        case .image: return "image"
        case .textField, .secureTextField: return "field"
        case .switch: return "switch"
        default: return "element"
        }
    }
}

// MARK: - Copy: words a user should never see

@MainActor
enum Copy {
    static let rules: [(pattern: String, severity: String, why: String)] = [
        ("[\u{2014}\u{2013}]", "P1", "em or en dash in app copy"),
        ("\\bNaN\\b|\\binf\\b|(?<!\\w)-0(?![.,\\d])", "P0", "a number that failed to compute"),
        ("Optional\\(|\\bnil\\b|\\(null\\)|\\bundefined\\b", "P0", "a Swift value leaked into copy"),
        ("%(@|l{0,2}d|\\.?\\d*f)|\\{\\w*\\}|\\\\\\(", "P0", "an unformatted placeholder"),
        ("\\b(TODO|FIXME|Lorem ipsum|placeholder)\\b", "P1", "unfinished copy"),
        ("^[a-z][a-z0-9]*(_[a-z0-9]+){1,}$|^[a-z]+(\\.[a-z][a-zA-Z0-9]+){2,}$", "P2", "looks like a localization key or symbol name"),
    ]

    static func lint(_ leaves: [Leaf], context: QA.Context) {
        var seen = Set<String>()
        for leaf in leaves where leaf.type == .staticText || leaf.type == .button || leaf.type == .link {
            let text = leaf.label
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            for rule in rules where text.range(of: rule.pattern, options: .regularExpression) != nil {
                QA.record(context, "copy", rule.severity, text, "\(rule.why): \"\(text)\"")
            }
        }
    }
}

// MARK: - Apple's accessibility audit

@MainActor
enum Audit {
    static func severity(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .hitRegion, .contrast: return "P2"
        default: return "P3"
        }
    }

    static func name(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .textClipped: return "text-clipped"
        case .hitRegion: return "hit-region"
        case .contrast: return "contrast"
        case .dynamicType: return "dynamic-type"
        case .elementDetection: return "element-detection"
        case .sufficientElementDescription: return "element-description"
        case .trait: return "trait"
        default: return "audit-\(type.rawValue)"
        }
    }

    static func run(_ app: XCUIApplication, shot: UIImage, leaves: [Leaf] = [], context: QA.Context) {
        let pixels = Idle.pixels(shot)
        do {
            var checked = 0
            // Dynamic Type and clipped-text checks re-render the app at other text
            // sizes, which shows on video and moves the layout under the other
            // oracles. The accessibility persona measures what AX3 really draws instead.
            // On the unfolded Duo the contrast check outlives the audit's timeout on a
            // dense split screen and keeps running in testmanagerd until the sim stalls.
            // The phone personas check the same colors.
            var types = XCUIAccessibilityAuditType.all.subtracting([.dynamicType, .textClipped])
            if QA.persona == "duo" { types.remove(.contrast) }
            try app.performAccessibilityAudit(for: types) { issue in
                // The audit walks hidden tabs too. Skip what nobody can see,
                // within a budget so a long screen cannot stall the gate.
                if let target = issue.element, checked < 40 {
                    checked += 1
                    if !(target.exists && target.isHittable) { return true }
                }
                let element = issue.element.map { $0.identifier.isEmpty ? $0.label : $0.identifier } ?? ""
                var measured = ""
                if issue.auditType == .contrast, let target = issue.element, let pixels {
                    // The audit flags text that passes (white on a dark brand color, iOS's own
                    // headers); a finding stands only when the drawn pixels fail WCAG too.
                    // The audit scrolls and re-renders as it goes, so the live frame can sit
                    // elsewhere than the screenshot drew the element; take the frame the
                    // tree had when the screenshot was taken.
                    let label = target.label, type = target.elementType
                    let frame = leaves.first { $0.label == label && $0.type == type }?.frame ?? target.frame
                    guard let ratio = contrast(in: frame, pixels, scale: CGFloat(pixels.width) / shot.size.width)
                    else { return true }
                    if ratio >= (frame.height >= 24 ? 3 : 4.5) { return true }
                    measured = String(format: " (measured %.1f:1)", ratio)
                }
                QA.record(context, "a11y-" + name(issue.auditType), severity(issue.auditType), element,
                          "\(issue.compactDescription)\(measured)\(element.isEmpty ? "" : ": \"\(element)\"")")
                return true
            }
        } catch {
            QA.record(context, "a11y-audit", "P3", "", "audit could not run: \(error.localizedDescription)")
        }
    }
}

extension Audit {
    /// WCAG contrast of the text drawn in `frame` (points): the commonest color is the
    /// background, and the text is what stands furthest from it among the pixels that
    /// differ (98th percentile: thin glyphs are mostly antialiased edge). Nil when nothing
    /// is drawn there.
    static func contrast(in frame: CGRect, _ image: (data: [UInt8], width: Int, height: Int), scale: CGFloat) -> Double? {
        let box = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale,
                         height: frame.height * scale).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard box.width >= 4, box.height >= 4 else { return nil }
        var counts: [Int: Int] = [:]
        var lums: [Double] = []
        for y in stride(from: Int(box.minY), to: Int(box.maxY), by: 1) {
            for x in stride(from: Int(box.minX), to: Int(box.maxX), by: 1) {
                let i = (y * image.width + x) * 4
                let r = image.data[i], g = image.data[i + 1], b = image.data[i + 2]
                counts[Int(r >> 4) << 8 | Int(g >> 4) << 4 | Int(b >> 4), default: 0] += 1
                lums.append(luminance(r, g, b))
            }
        }
        guard let mode = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let channel = { (shift: Int) in UInt8(((mode >> shift) & 0xF) * 17) }
        let background = luminance(channel(8), channel(4), channel(0))
        let ink = lums.map { (max($0, background) + 0.05) / (min($0, background) + 0.05) }.filter { $0 > 1.15 }.sorted()
        guard !ink.isEmpty else { return nil }
        return ink[min(ink.count - 1, Int(Double(ink.count) * 0.98))]
    }

    static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

// MARK: - Idle: a settled screen should stop drawing

@MainActor
enum Idle {
    /// Compares two screenshots a second apart. A screen that keeps changing
    /// with nothing declared ambient burns battery and makes every capture of
    /// it a coin toss.
    static func check(_ app: XCUIApplication, first: UIImage, ambient: [Leaf], context: QA.Context) {
        sleep(1)
        let second = QA.capture(app)
        guard let a = pixels(first), let b = pixels(second), a.data.count == b.data.count else { return }
        let skip = ambient.map(\.frame)
        let scale = CGFloat(a.width) / max(first.size.width, 1)
        var changed = 0, total = 0
        var box = CGRect.null
        let statusBar = Int(60 * scale)
        for y in stride(from: statusBar, to: a.height, by: 2) {
            for x in stride(from: 0, to: a.width, by: 2) {
                let point = CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale)
                if skip.contains(where: { $0.contains(point) }) { continue }
                total += 1
                let i = (y * a.width + x) * 4
                let delta = abs(Int(a.data[i]) - Int(b.data[i])) + abs(Int(a.data[i + 1]) - Int(b.data[i + 1]))
                    + abs(Int(a.data[i + 2]) - Int(b.data[i + 2]))
                if delta > 24 {
                    changed += 1
                    box = box.union(CGRect(origin: point, size: CGSize(width: 1, height: 1)))
                }
            }
        }
        guard total > 0, Double(changed) / Double(total) > 0.001 else { return }
        QA.record(context, "never-idle", "P3", "",
                  String(format: "screen still drawing a second after it settled: %.1f%% of pixels changed in x %.0f to %.0f, y %.0f to %.0f",
                         100 * Double(changed) / Double(total), box.minX, box.maxX, box.minY, box.maxY))
    }

    static func pixels(_ image: UIImage) -> (data: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (data, width, height) : nil
    }
}

// MARK: - Render: what is actually drawn, read back with on-device OCR

@MainActor
enum Render {
    struct Line {
        let text: String
        let frame: CGRect
        /// Each word with its own box: one OCR line can run across two elements.
        var words: [Line] = []
    }

    /// Every line of text in the screenshot, with its frame in points.
    static func read(_ shot: UIImage) -> [Line] {
        guard let image = shot.cgImage else { return [] }
        let size = shot.size
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        func points(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                   width: box.width * size.width, height: box.height * size.height)
        }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            var words: [Line] = []
            var index = text.startIndex
            for word in text.split(separator: " ") {
                guard let range = text.range(of: word, range: index..<text.endIndex) else { continue }
                index = range.upperBound
                if let box = try? candidate.boundingBox(for: range)?.boundingBox {
                    words.append(Line(text: String(word), frame: points(box)))
                }
            }
            return Line(text: text, frame: points(observation.boundingBox), words: words)
        }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 }
    }

    /// Share of the element's words that are drawn inside its frame: 0 for a
    /// hidden element, 1 for text that reads cleanly.
    static func presence(_ leaf: Leaf, _ lines: [Line], excluding other: String = "") -> Double {
        let shared = Set(words(other))
        let wanted = words(leaf.label).filter { !shared.contains($0) }
        guard !wanted.isEmpty else { return 1 }
        let drawn = lines.filter { leaf.frame.insetBy(dx: -4, dy: -4).intersects($0.frame) }.map { $0.text.lowercased() }.joined(separator: " ")
        return Double(wanted.filter { drawn.contains($0) }.count) / Double(wanted.count)
    }

    /// True when OCR drew text in `region` that no element reading cleanly
    /// there accounts for (a hidden TabView tab sits under a visible one that does).
    static func unexplained(in region: CGRect, _ lines: [Line], leaves: [Leaf]) -> Bool {
        let clean = leaves.filter { presence($0, lines) >= 0.9 && !words($0.label).isEmpty }
        return lines.contains { line in
            guard line.frame.intersects(region), !words(line.text).isEmpty else { return false }
            let middle = CGPoint(x: line.frame.midX, y: line.frame.midY)
            // A wrapped label's later lines miss its first word, so match on the line's own words.
            let drawn = words(line.text)
            return !clean.contains { leaf in
                let label = Set(words(leaf.label))
                return leaf.frame.insetBy(dx: -4, dy: -4).contains(middle)
                    && drawn.filter { label.contains($0) }.count * 2 >= drawn.count
            }
        }
    }

    /// Text drawn with an ellipsis its label does not have was cut off: a price,
    /// a plan name or a button title the user cannot read in full.
    static func truncation(_ leaves: [Leaf], _ lines: [Line], context: QA.Context) {
        var seen = Set<String>()
        for leaf in leaves where leaf.type == .staticText || leaf.type == .button {
            guard !leaf.label.contains("…"), !leaf.label.contains("..."), seen.insert(leaf.label).inserted else { continue }
            for line in lines where leaf.frame.insetBy(dx: -2, dy: -2).contains(CGPoint(x: line.frame.midX, y: line.frame.midY)) {
                let text = line.text.trimmingCharacters(in: .whitespaces)
                guard text.hasSuffix("…") || text.hasSuffix("...") else { continue }
                let stem = String(text.dropLast(text.hasSuffix("…") ? 1 : 3)).lowercased()
                guard stem.count >= 2, leaf.label.lowercased().contains(stem.suffix(min(stem.count, 6))) else { continue }
                QA.record(context, "truncated", "P1", leaf.name,
                          "\(Layout.typeName(leaf.type)) drawn as \"\(text)\" but reads \"\(leaf.label)\"")
                break
            }
        }
    }

    /// A one-word label (a number, a segment, a unit) drawn short with no
    /// ellipsis, or broken mid-word across lines: "63,5" for "63,542",
    /// "Cu / sto / m" for "Custom".
    static func clipped(_ leaves: [Leaf], _ lines: [Line], context: QA.Context) {
        var seen = Set<String>()
        for leaf in leaves where leaf.type == .staticText || leaf.type == .button {
            let label = leaf.label.trimmingCharacters(in: .whitespaces)
            guard label.count >= 3, !label.contains(" "), seen.insert(label).inserted else { continue }
            let frame = leaf.frame.insetBy(dx: -2, dy: -2)
            // One piece per drawn line, from the words whose centre is inside the element.
            let pieces = lines.sorted { $0.frame.minY < $1.frame.minY }.compactMap { line -> String? in
                let words = (line.words.isEmpty ? [line] : line.words)
                    .filter { frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                let piece = words.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                return piece.isEmpty ? nil : piece
            }
            guard !pieces.isEmpty else { continue }
            // Compare letters and digits only: OCR adds stray marks ("•sto") and drops commas.
            let plain = { (text: String) in text.lowercased().filter { $0.isLetter || $0.isNumber } }
            let joined = pieces.joined()
            // OCR can lose a short first piece ("Cu"), so the rest in order is enough.
            if pieces.count >= 2, plain(joined).count >= 3, plain(label).contains(plain(joined)) {
                QA.record(context, "clipped", "P1", leaf.name,
                          "\(Layout.typeName(leaf.type)) \"\(label)\" is broken across \(pieces.count) lines: \(pieces.joined(separator: " / "))")
                continue
            }
            // A clipped element's frame can be wider than what it draws and take in
            // a neighbour's first word ("1,234, sto"), so keep the leading words that
            // still spell the start of the label.
            // A neighbour's word on a line above ("Cu") can come first, so take the
            // line whose leading words spell the most of it.
            let lead = pieces.map { piece in
                piece.split(separator: " ").reduce(into: (text: "", open: true)) { run, word in
                    let next = run.text.isEmpty ? String(word) : run.text + " " + word
                    if run.open && plain(label).hasPrefix(plain(next)) { run.text = next } else { run.open = false }
                }.text
            }.max { plain($0).count < plain($1).count } ?? ""
            if plain(lead).count >= 2, plain(lead).count < plain(label).count, !lead.hasSuffix("…"), !lead.hasSuffix("...") {
                QA.record(context, "clipped", "P1", leaf.name,
                          "\(Layout.typeName(leaf.type)) drawn as \"\(lead)\" but reads \"\(label)\", cut off with no ellipsis")
            }
        }
    }
}

// MARK: - States: error copy, blank screens, endless spinners

@MainActor
enum States {
    /// Copy that means the screen failed to get what it needed. Journeys run on
    /// seeded data, so reaching one of these is a broken screen, not bad luck.
    static let failure = #"couldn['’]?t load|could not load|unable to load|failed to load|error loading"#
        + #"|something went wrong|try again later|no (plans|products|offerings|subscriptions) (are )?(available|found)"#
        + #"|(plans|products|prices) (are )?(not |un)available|not available right now|no internet|connection (error|failed)"#

    static func check(_ leaves: [Leaf], _ rendered: [Render.Line], height: CGFloat, context: QA.Context) {
        let texts = leaves.filter { $0.type == .staticText || $0.type == .button }.map(\.label) + rendered.map(\.text)
        if let text = texts.first(where: { $0.range(of: failure, options: [.regularExpression, .caseInsensitive]) != nil }) {
            QA.record(context, "error-state", "P1", text, "the screen shows a failure: \"\(text)\"")
        }
        // Below the status bar, a screen with almost nothing to read is blank
        // (a paywall that never rendered, a white sheet after relaunch).
        let drawn = rendered.filter { $0.frame.minY > 60 && !Render.words($0.text).isEmpty }
        let labelled = leaves.filter { !$0.label.isEmpty && $0.frame.minY > 60 && $0.frame.minY < height }
        if drawn.count < 2 && labelled.count < 2 {
            QA.record(context, "blank-screen", "P1", "",
                      "the screen is blank: \(drawn.count) line(s) drawn, \(labelled.count) labelled element(s)")
        }
    }

    /// A spinner still turning once the screen has been watched for `seconds`:
    /// the user is left waiting on something that is not coming.
    static func spinner(_ app: XCUIApplication, seconds: TimeInterval, context: QA.Context) {
        guard let leaf = Layout.leaves(app)?.leaves.first(where: { $0.type == .activityIndicator }) else { return }
        QA.record(context, "still-loading", "P1", leaf.name,
                  String(format: "a spinner is still showing %.0fs into the step", seconds))
    }
}

// MARK: - Anchor: the main button stays put from one step to the next

@MainActor
enum Anchor {
    /// The previous checkpoint's main button, with its journey.
    static var last: (journey: String, checkpoint: String, frame: CGRect)?

    /// The largest button in the bottom 40% of the screen, at least half the screen wide.
    static func primary(_ leaves: [Leaf], width: CGFloat, height: CGFloat) -> Leaf? {
        leaves.filter { $0.type == .button && !$0.inScroll && $0.frame.width >= width * 0.5 && $0.frame.midY >= height * 0.6 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// Onboarding and paywall steps share one call to action. When it jumps
    /// between steps (legal text pushing it up, a "Not now" row nudging it) the
    /// thumb misses and the flow feels unfinished.
    static func check(_ app: XCUIApplication, _ leaves: [Leaf], width: CGFloat, height: CGFloat, context: QA.Context) {
        // A keyboard lifts the button on purpose.
        guard app.keyboards.count == 0, let button = primary(leaves, width: width, height: height) else {
            last = nil
            return
        }
        defer { last = (context.journey, context.checkpoint, button.frame) }
        guard let before = last, before.journey == context.journey else { return }
        let a = button.frame, b = before.frame
        guard max(abs(a.minY - b.minY), abs(a.height - b.height), abs(a.minX - b.minX), abs(a.width - b.width)) > 2 else { return }
        QA.record(context, "cta-jump", "P1", button.name,
                  String(format: "the main button \"%@\" is at y %.0f, %.0f by %.0f; on \"%@\" it was at y %.0f, %.0f by %.0f",
                         button.name, a.minY, a.width, a.height, before.checkpoint, b.minY, b.width, b.height))
    }
}

// MARK: - Paywall: what App Review checks on every purchase screen (3.1.1, 3.1.2)

@MainActor
enum Paywall {
    static let named = #"paywall|upgrade|trial|pitch|offer|plans|subscri|purchase"#
    static let after = #"dismiss|closed|after|return|back|done"#
    static let price = #"(?:US\$|CA\$|A\$|[$€£¥₹])\s?\d[\d.,]*|\d[\d.,]*\s?(?:[$€£¥₹]|kr|zł|CHF)"#
    static let period = #"year|annual|month|week|/\s?(yr|mo|wk)\b|trial"#
    static let derived = #"/\s?(mo|month|wk|week|day)\b|(per|a|each) (month|week|day)\b"#
    static let yearly = #"year|annual|/\s?yr\b"#

    /// A purchase screen: the checkpoint is named like one and something on
    /// screen sells (a priced plan, a visible Restore, a subscribe or trial
    /// button), or a priced plan sits next to a visible Restore. Restore alone
    /// is not enough: a Settings tab keeps its Restore row in the tree behind
    /// every other tab.
    static func looksLike(_ app: XCUIApplication, name: String, leaves: [Leaf]) -> Bool {
        let restore = find(app, "restore")?.isHittable ?? false
        let priced = leaves.contains { leaf in
            leaf.label.range(of: price, options: .regularExpression) != nil
                && leaf.label.range(of: period, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let pitch = leaves.contains { leaf in
            leaf.type == .button && leaf.label.range(of: #"subscribe|start .*trial|try .*free"#,
                                                     options: [.regularExpression, .caseInsensitive]) != nil
        }
        let saysSo = name.range(of: named, options: [.regularExpression, .caseInsensitive]) != nil
            && name.range(of: after, options: [.regularExpression, .caseInsensitive]) == nil
        return (saysSo && (restore || priced || pitch)) || (priced && restore)
    }

    /// The words each paywall control goes by in the persona languages
    /// (the `german` persona included), so a localized paywall passes.
    static let words: [String: [String]] = [
        "restore": ["restore", "wiederherstellen"],
        "terms": ["terms", "EULA", "nutzungsbedingungen", "bedingungen"],
        "privacy": ["privacy", "datenschutz"],
    ]

    /// An element anywhere in the tree, scrolled off or not, whose label contains `text`
    /// or one of its translations in `words`.
    static func find(_ app: XCUIApplication, _ text: String) -> XCUIElement? {
        let predicates = (words[text] ?? [text]).map { NSPredicate(format: "label CONTAINS[c] %@", $0) }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        return [app.buttons, app.links, app.staticTexts].lazy.map { $0.matching(predicate).firstMatch }.first { $0.exists }
    }

    /// The first price in `text` as a number: "$29.99" 29.99, "29,99 €" 29.99, "1.299 kr" 1299.
    static func amount(_ text: String) -> Double? {
        guard let range = text.range(of: price, options: .regularExpression) else { return nil }
        let raw = String(text[range].filter { $0.isNumber || $0 == "." || $0 == "," })
        guard let last = raw.lastIndex(where: { $0 == "." || $0 == "," }),
              raw.distance(from: last, to: raw.endIndex) == 3 else { return Double(raw.filter(\.isNumber)) }
        return Double(raw[..<last].filter(\.isNumber) + "." + raw[raw.index(after: last)...])
    }

    static func check(_ app: XCUIApplication, _ leaves: [Leaf], _ rendered: [Render.Line], context: QA.Context) {
        let drawn = rendered.filter { $0.text.range(of: price, options: .regularExpression) != nil }
        if drawn.isEmpty && !leaves.contains(where: { $0.label.range(of: price, options: .regularExpression) != nil }) {
            QA.record(context, "paywall-price", "P0", "", "a paywall with no price on screen: the plans did not load or the price is hidden")
        }
        if find(app, "terms") == nil {
            QA.record(context, "paywall-terms", "P1", "", "no Terms of Use (EULA) link anywhere on the paywall (3.1.2)")
        }
        if find(app, "privacy") == nil {
            QA.record(context, "paywall-privacy", "P1", "", "no Privacy Policy link anywhere on the paywall (3.1.2)")
        }
        if find(app, "restore") == nil {
            QA.record(context, "paywall-restore", "P2", "", "no Restore Purchases control on the paywall (3.1.1)")
        }
        prominence(drawn, context: context)
    }

    /// 3.1.2(c): the billed amount must be the most prominent price. A monthly
    /// or weekly figure worked out from the yearly price ($2.49/mo for
    /// $29.99/year) may not be drawn larger than the yearly price itself.
    static func prominence(_ drawn: [Render.Line], context: QA.Context) {
        let priced = drawn.compactMap { line in amount(line.text).map { (line: line, amount: $0) } }
        let years = priced.filter { $0.line.text.range(of: yearly, options: [.regularExpression, .caseInsensitive]) != nil }
        let computed = priced.filter { item in
            item.line.text.range(of: derived, options: [.regularExpression, .caseInsensitive]) != nil
                && years.contains { year in [12.0, 52.0, 365.0].contains { abs(year.amount / $0 - item.amount) <= max(0.02, item.amount * 0.03) } }
        }
        guard let loudest = computed.max(by: { $0.line.frame.height < $1.line.frame.height }),
              let billed = years.max(by: { $0.line.frame.height < $1.line.frame.height }),
              loudest.line.frame.height > billed.line.frame.height * 1.15 else { return }
        QA.record(context, "paywall-prominence", "P1", loudest.line.text,
                  String(format: "\"%@\" (worked out from the yearly price) is drawn %.0fpt tall, larger than the billed \"%@\" at %.0fpt (3.1.2(c))",
                         loudest.line.text, loudest.line.frame.height, billed.line.text, billed.line.frame.height))
    }
}
