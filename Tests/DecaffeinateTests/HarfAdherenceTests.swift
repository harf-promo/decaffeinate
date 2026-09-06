import XCTest

@testable import Decaffeinate

/// The Harf design-system gate — the lexical half.
///
/// These rules govern values that only exist in source text (a corner radius, an
/// animation duration, a font size), so they are checked by reading the app's own
/// source rather than by running it. See `docs/DESIGN.md` for the contract and
/// for the deviations this app has deliberately sanctioned.
///
/// **How the ledgers work.** Each rule carries the number of violations that
/// existed when the gate was written. The assertion is exact equality, not "no
/// worse than": a phase that fixes violations MUST decrement its ledger in the
/// same commit, so every later diff shows the improvement as a number a reviewer
/// can check at a glance, and a phase that adds one fails immediately.
final class HarfAdherenceTests: XCTestCase {

    /// Violations present when this gate was introduced (Phase 0). Decrement as
    /// each phase lands; a rule reaching 0 stays at 0.
    private enum Ledger {
        /// Squircle corner style. Harf ships `--r-0/1/2/pill` and no superellipse.
        static let continuousCornerStyle = 12
        /// Resting shadows. Harf's structure is hairlines.
        static let restingShadow = 0
        /// Font sizes off the 5/4 type ladder.
        static let offLadderFontSize = 28
        /// Animation durations off the x2 motion ladder.
        static let offLadderDuration = 4
        /// Motion not gated on Reduce Motion.
        static let ungatedMotion = 9
    }

    /// The only legal type sizes: 16 x 1.25^n, plus the named 12px half-rung.
    private static let typeLadder: Set<Int> = [
        10, 12, 13, 16, 20, 25, 31, 39, 49, 61, 76, 95, 119, 149, 186, 233,
    ]

    /// The only legal animation durations, in seconds: the x2 ladder.
    private static let motionLadder: Set<Double> = [0.05, 0.1, 0.2, 0.4, 0.8]

    // MARK: - Shape

    /// Harf's radii are `{0, 2, 4, pill}` and none of them is a superellipse.
    ///
    /// `AppIconProvider` is exempt by design: its `.continuous` mask is the macOS
    /// app-icon shape, applied to *other* applications' icons in blocker rows.
    /// Harf's no-squircle rule governs Harf's own containers, not Apple's.
    func testNoContinuousCornerStyleOutsideTheAppIconMask() throws {
        let hits = try SourceScanner.scan(
            under: "Views", skippingFiles: ["AppIconProvider.swift"]
        ) { $0.contains("style: .continuous") }
        assertLedger(hits, equals: Ledger.continuousCornerStyle, rule: "style: .continuous")
    }

    /// Hairlines, not shadows.
    ///
    /// `SleepWarningHUD` is exempt: it is a borderless floating panel over an
    /// arbitrary desktop, the one place macOS needs an edge that a hairline on an
    /// unknown background cannot provide. See `docs/DESIGN.md`.
    func testNoRestingShadowsOutsideTheFloatingPanel() throws {
        let hits = try SourceScanner.scan(
            under: "Views", skippingFiles: ["SleepWarningHUD.swift"]
        ) { $0.contains(".shadow(") }
        assertLedger(hits, equals: Ledger.restingShadow, rule: ".shadow( on a resting surface")
    }

    // MARK: - Type

    /// Every font size sits on the 5/4 ladder.
    ///
    /// The whole line is scanned, not just the leading argument: the compact
    /// button writes its size as `compact ? 12 : 14`, and a gate that read only
    /// the first token would score that illegal 14 as compliant.
    func testEveryFontSizeIsOnTheTypeLadder() throws {
        let hits = try SourceScanner.scan(under: "Views") { line in
            let sized = line.contains("scaledFont(") || line.contains("system(size:")
            guard sized else { return false }
            let sizes = SourceScanner.integerLiterals(in: line)
            return sizes.contains { !Self.typeLadder.contains($0) }
        }
        assertLedger(hits, equals: Ledger.offLadderFontSize, rule: "font size off the 5/4 ladder")
    }

    // MARK: - Motion

    /// Every animation duration sits on the x2 ladder: 50/100/200/400/800ms.
    func testEveryAnimationDurationIsOnTheMotionLadder() throws {
        let hits = try SourceScanner.scan(under: "Views") { line in
            Self.durations(in: line).contains { !Self.motionLadder.contains($0) }
        }
        assertLedger(hits, equals: Ledger.offLadderDuration, rule: "duration off the x2 ladder")
    }

    /// Every animation is gated on Reduce Motion.
    ///
    /// Counted, not banned: motion is legitimate, and the fix is to route it
    /// through the shared reduce-motion-aware modifier rather than to delete it.
    /// A site counts as gated once it no longer names a raw SwiftUI animation.
    func testEveryAnimationIsGatedOnReduceMotion() throws {
        let hits = try SourceScanner.scan(under: "Views") { line in
            line.contains(".animation(") || line.contains("withAnimation(")
                || line.contains(".transition(")
        }
        assertLedger(hits, equals: Ledger.ungatedMotion, rule: "motion not gated on Reduce Motion")
    }

    // MARK: - Helpers

    /// The number after every `duration:` label on a line, in seconds.
    ///
    /// Deliberately narrower than "every number on the line": `withAnimation(...)
    /// { page += 1 }` carries an unrelated `1` that a whole-line scan would read
    /// as a one-second animation.
    private static func durations(in line: String) -> [Double] {
        var values: [Double] = []
        var rest = Substring(line)
        while let label = rest.range(of: "duration:") {
            rest = rest[label.upperBound...]
            let number = rest.prefix { $0 == " " || $0 == "." || $0.isNumber }
                .drop { $0 == " " }
            if let value = Double(number) { values.append(value) }
        }
        return values
    }

    private func assertLedger(
        _ hits: [SourceScanner.Hit], equals expected: Int, rule: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard hits.count != expected else { return }
        let verb = hits.count > expected ? "grew" : "shrank"
        let listing = hits.map { "    \($0.report)" }.joined(separator: "\n")
        XCTFail(
            """
            Harf gate "\(rule)" \(verb): \(expected) -> \(hits.count).
            If you fixed sites, decrement this rule's ledger in HarfAdherenceTests \
            so the improvement is visible in the diff. If you added one, use the \
            token layer instead — or record a sanctioned deviation in docs/DESIGN.md \
            and add the file to this rule's skip list.
            \(listing)
            """,
            file: file, line: line)
    }
}
