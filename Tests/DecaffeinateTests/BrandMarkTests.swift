import XCTest

@testable import Decaffeinate

final class BrandMarkTests: XCTestCase {
    // ── logo() ────────────────────────────────────────────────────────────────

    func testLogoContainsMoonAndCup() {
        // The moon-in-cup mark: a green crescent + steam-z (.moon) and a
        // porcelain cup + star (.cream).
        let elements = BrandMark.logo(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertFalse(elements.isEmpty)
        XCTAssertTrue(
            elements.contains { $0.ink == .moon }, "logo must include a green moon/steam element")
        XCTAssertTrue(
            elements.contains { $0.ink == .cream }, "logo must include a porcelain cup element")
    }

    func testLogoElementsHaveNonEmptyPaths() {
        let elements = BrandMark.logo(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        for (i, el) in elements.enumerated() {
            XCTAssertFalse(el.path.isEmpty, "logo element \(i) must have a non-empty path")
        }
    }

    func testCrescentElementUsesNonZeroFill() {
        // The crescent is a single arc-traced lune (not an even-odd carve of two
        // circles, which would fill both opposing lunes into a ring). It must be
        // filled non-zero so the moon shape appears solid.
        let elements = BrandMark.logo(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertTrue(
            elements.contains { $0.ink == .moon && !$0.evenOdd },
            "logo must contain a non-zero-filled crescent element")
    }

    func testLogoScalesToDifferentSizes() {
        for size in [18, 64, 256, 1024] as [CGFloat] {
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let elements = BrandMark.logo(in: rect)
            XCTAssertFalse(elements.isEmpty, "logo must render at \(size)px")
            for el in elements {
                let bb = el.path.boundingBox
                XCTAssertFalse(bb.isNull, "path bounding box must not be null at \(size)px")
            }
        }
    }

    // ── menuGlyph() ───────────────────────────────────────────────────────────

    func testMenuGlyphCoversAllStates() {
        let rect = CGRect(x: 0, y: 0, width: 18, height: 18)
        for state in [MugState.free, .counting, .blocked, .caffeinated] {
            let elements = BrandMark.menuGlyph(for: state, in: rect)
            XCTAssertFalse(elements.isEmpty, "\(state) glyph must not be empty")
            for (i, el) in elements.enumerated() {
                XCTAssertFalse(
                    el.path.isEmpty,
                    "\(state) glyph element \(i) must have a non-empty path")
            }
        }
    }

    func testMenuGlyphPathsAreWithinBounds() {
        let size: CGFloat = 18
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        // Allow 1 pt of overflow for rounding; the template image clips at the edge.
        let expanded = rect.insetBy(dx: -1, dy: -1)
        for state in [MugState.free, .counting, .blocked, .caffeinated] {
            for el in BrandMark.menuGlyph(for: state, in: rect) {
                let bb = el.path.boundingBox
                XCTAssertTrue(
                    expanded.contains(bb),
                    "\(state) path bounding box \(bb) overflows the \(rect) rect by more than 1pt")
            }
        }
    }

    func testMenuGlyphStatesDifferByShape() {
        // Each state must produce a DIFFERENT combined bounding-box set so they
        // are visually distinct at 18px.  Two states sharing identical bounding
        // boxes would be indistinguishable in the template image.
        let rect = CGRect(x: 0, y: 0, width: 18, height: 18)
        let states = [MugState.free, .counting, .blocked, .caffeinated]
        let bboxSets = states.map { state -> CGRect in
            // Union all element bboxes into one representative rect for the state.
            BrandMark.menuGlyph(for: state, in: rect)
                .reduce(CGRect.null) { $0.union($1.path.boundingBox) }
        }
        // All four must be unique.
        let unique = Set(bboxSets.map { "\($0)" })
        XCTAssertEqual(
            unique.count, states.count,
            "each MugState must produce a unique composite bounding box")
    }

    // ── Primitive: crescent ──────────────────────────────────────────────────

    func testCrescentPathIsNotEmpty() {
        let path = BrandMark.crescent(cx: 32, cy: 32, r: 18)
        XCTAssertFalse(path.isEmpty)
    }

    func testCrescentPathIsOneClosedLune() {
        // The crescent is one closed lune (outer moon arc + inner carve arc),
        // not two separate ellipses.
        let path = BrandMark.crescent(cx: 32, cy: 32, r: 18)
        var closeCount = 0
        path.applyWithBlock { el in
            if el.pointee.type == .closeSubpath { closeCount += 1 }
        }
        XCTAssertEqual(closeCount, 1, "crescent path must be a single closed sub-path")
    }

    func testCrescentIsAWideMouthedMoonNotARing() {
        // Regression guard: the old mark carved with ~0.76r radius at a ~0.25r
        // offset, reaching only ~1.007r past the centre — the "moon" read as a
        // near-closed ring. The carve must reach well past the rim so a real
        // crescent mouth opens.
        XCTAssertGreaterThan(
            BrandMark.crescentReachRatio, 1.2,
            "the carve must clear the rim so the moon reads as a crescent, not a ring")

        // And prove it on the geometry: a point out toward the carve mouth is
        // OPEN (carved away), while the fat side (opposite the carve) is FILLED.
        let r: CGFloat = 100
        let path = BrandMark.crescent(cx: 0, cy: 0, r: r)
        let mouth = CGPoint(x: 0.94 * 0.7 * r, y: -0.34 * 0.7 * r)  // toward the carve
        let fatSide = CGPoint(x: -0.94 * 0.775 * r, y: 0.34 * 0.775 * r)  // opposite the carve
        XCTAssertFalse(
            path.contains(mouth, using: .evenOdd), "the crescent mouth must be open, not filled")
        XCTAssertTrue(
            path.contains(fatSide, using: .evenOdd), "the crescent's fat side must be solid")
    }

    // ── Primitive: zGlyph ────────────────────────────────────────────────────

    func testZGlyphIsNotEmpty() {
        let path = BrandMark.zGlyph(x: 0, y: 0, w: 20, h: 16)
        XCTAssertFalse(path.isEmpty)
    }

    func testZGlyphFitsInBoundingBox() {
        let w: CGFloat = 20, h: CGFloat = 16
        let path = BrandMark.zGlyph(x: 5, y: 5, w: w, h: h)
        let bb = path.boundingBox
        // Bounding box must be contained in (or equal to) the specified rect.
        let expected = CGRect(x: 5, y: 5, width: w, height: h)
        XCTAssertTrue(
            expected.insetBy(dx: -0.5, dy: -0.5).contains(bb),
            "Z glyph path bounding box \(bb) must fit in \(expected)")
    }
}
