import XCTest

@testable import Decaffeinate

final class BrandMarkTests: XCTestCase {
    // ── logo() ────────────────────────────────────────────────────────────────

    func testLogoContainsMoonAndZzz() {
        let elements = BrandMark.logo(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertFalse(elements.isEmpty)
        XCTAssertTrue(
            elements.contains { $0.ink == .moon }, "logo must include a moon element")
        XCTAssertTrue(
            elements.contains { $0.ink == .zzz }, "logo must include zzz elements")
    }

    func testLogoElementsHaveNonEmptyPaths() {
        let elements = BrandMark.logo(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        for (i, el) in elements.enumerated() {
            XCTAssertFalse(el.path.isEmpty, "logo element \(i) must have a non-empty path")
        }
    }

    func testMoonElementUsesEvenOddFill() {
        let elements = BrandMark.logo(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let moon = elements.first(where: { $0.ink == .moon }) else {
            XCTFail("logo must contain a moon element"); return
        }
        XCTAssertTrue(
            moon.evenOdd, "the crescent must use even-odd fill so the carve hole appears")
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

    func testCrescentPathContainsTwoSubpaths() {
        // The crescent is two overlapping ellipses; CGPath breaks each ellipse
        // into a moveTo + curves + close, so the path should have two closePath ops.
        let path = BrandMark.crescent(cx: 32, cy: 32, r: 18)
        var closeCount = 0
        path.applyWithBlock { el in
            if el.pointee.type == .closeSubpath { closeCount += 1 }
        }
        XCTAssertEqual(closeCount, 2, "crescent path must contain exactly two closed sub-paths")
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
