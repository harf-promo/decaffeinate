import AppKit

/// Renders Decaffeinate's app icon — the "Moon + Zzz" mark on a dark night
/// field — and outputs `icon-1024.png`, `AppIcon.icns`, and
/// `decaffeinate-mark.svg` to a directory. Driven by `Decaffeinate --icon <dir>`.
@MainActor
enum IconRenderer {
    // Brand palette (same constants as HarfTheme; duplicated so IconRenderer has
    // no SwiftUI dependency and can be used from a headless CLI context).
    // Night gradient poles (top → bottom) behind the mark.
    private static let nightTop = CGColor(
        srgbRed: 0x23 / 255, green: 0x25 / 255, blue: 0x2E / 255, alpha: 1)
    private static let nightBottom = CGColor(
        srgbRed: 0x12 / 255, green: 0x13 / 255, blue: 0x18 / 255, alpha: 1)
    private static let moonColor = CGColor(
        srgbRed: 0xA4 / 255, green: 0xCD / 255, blue: 0x39 / 255, alpha: 1)
    private static let zColor = CGColor(
        srgbRed: 0x93 / 255, green: 0x95 / 255, blue: 0x98 / 255, alpha: 1)
    // Porcelain — the cup and stars.
    private static let creamColor = CGColor(
        srgbRed: 0xF2 / 255, green: 0xED / 255, blue: 0xE4 / 255, alpha: 1)

    private static func fill(for ink: BrandMark.Ink) -> CGColor {
        switch ink {
        case .moon: return moonColor
        case .zzz: return zColor
        case .cream: return creamColor
        }
    }

    // SVG hex per role (matches the fills above).
    private static func svgHex(for ink: BrandMark.Ink) -> String {
        switch ink {
        case .moon: return "#A4CD39"
        case .zzz: return "#939598"
        case .cream: return "#F2EDE4"
        }
    }

    // ── Public entry point ────────────────────────────────────────────────────

    @discardableResult
    static func renderAll(to directory: String) -> Bool {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: directory)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let master = renderIcon(size: 1024)

        // Write icon-1024.png.
        guard let pngData = png(master, size: 1024) else {
            print("Error: could not render icon-1024.png"); return false
        }
        do {
            try pngData.write(to: dir.appendingPathComponent("icon-1024.png"))
        } catch {
            print("Error writing icon-1024.png: \(error)"); return false
        }

        // Build .iconset → iconutil → AppIcon.icns.
        let iconsetURL = dir.appendingPathComponent("AppIcon.iconset")
        try? fm.removeItem(at: iconsetURL)
        try? fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        let variants: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, size) in variants {
            if let data = png(master, size: size) {
                try? data.write(to: iconsetURL.appendingPathComponent("\(name).png"))
            }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        task.arguments = [
            "-c", "icns", iconsetURL.path,
            "-o", dir.appendingPathComponent("AppIcon.icns").path,
        ]
        try? task.run()
        task.waitUntilExit()
        try? fm.removeItem(at: iconsetURL)

        // Export SVG from the same BrandMark geometry (no hand-written copy).
        writeSVG(to: dir.appendingPathComponent("decaffeinate-mark.svg"), size: 256)

        print("✅  Wrote icon-1024.png, AppIcon.icns, decaffeinate-mark.svg → \(dir.path)")
        return true
    }

    // ── Icon rendering ────────────────────────────────────────────────────────

    private static func renderIcon(size s: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()

        // Rounded-rect clip — macOS app-icon corner ratio.
        let corner = s * 0.2237
        let clip = NSBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
            xRadius: corner, yRadius: corner)
        clip.addClip()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus(); return img
        }

        // Night-sky gradient behind the mark (top lighter → bottom darker).
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [nightTop, nightBottom] as CFArray, locations: [0, 1])
        {
            ctx.saveGState()
            ctx.addPath(
                CGPath(
                    roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: corner, cornerHeight: corner, transform: nil))
            ctx.clip()
            ctx.drawLinearGradient(
                gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0),
                options: [])
            ctx.restoreGState()
        }

        // BrandMark is y-down; lockFocus is y-up — flip the CTM.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1, y: -1)

        for el in BrandMark.logo(in: CGRect(x: 0, y: 0, width: s, height: s)) {
            ctx.setFillColor(fill(for: el.ink))
            ctx.addPath(el.path)
            ctx.fillPath(using: el.evenOdd ? .evenOdd : .winding)
        }

        ctx.restoreGState()
        img.unlockFocus()
        return img
    }

    private static func png(_ image: NSImage, size: CGFloat) -> Data? {
        let target = NSImage(size: NSSize(width: size, height: size))
        target.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        rep.size = NSSize(width: size, height: size)
        return rep.representation(using: .png, properties: [:])
    }

    // ── SVG export ────────────────────────────────────────────────────────────

    private static func writeSVG(to url: URL, size: CGFloat) {
        let sz = Int(size)
        let corner = String(format: "%.1f", size * 0.2237)
        var lines = [
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
            "<svg xmlns=\"http://www.w3.org/2000/svg\""
                + " viewBox=\"0 0 \(sz) \(sz)\" width=\"\(sz)\" height=\"\(sz)\">",
            // Night-sky gradient background — parity with the PNG/ICNS icon
            // (the SVG used to export the mark on a transparent canvas).
            "  <defs><linearGradient id=\"night\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">",
            "    <stop offset=\"0\" stop-color=\"#23252E\"/>",
            "    <stop offset=\"1\" stop-color=\"#121318\"/>",
            "  </linearGradient></defs>",
            "  <rect width=\"\(sz)\" height=\"\(sz)\" rx=\"\(corner)\" fill=\"url(#night)\"/>",
        ]
        for el in BrandMark.logo(in: CGRect(x: 0, y: 0, width: size, height: size)) {
            let fill = svgHex(for: el.ink)
            let rule = el.evenOdd ? "evenodd" : "nonzero"
            let d = svgPath(el.path)
            lines.append(
                "  <path fill=\"\(fill)\" fill-rule=\"\(rule)\" d=\"\(d)\"/>")
        }
        lines.append("</svg>")
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
    }

    /// Convert a `CGPath` to an SVG `d` attribute string (cubic-bezier segments).
    private static func svgPath(_ path: CGPath) -> String {
        var d = ""
        path.applyWithBlock { ptr in
            let el = ptr.pointee
            let pts = el.points
            switch el.type {
            case .moveToPoint:
                d += "M\(c(pts[0].x)),\(c(pts[0].y)) "
            case .addLineToPoint:
                d += "L\(c(pts[0].x)),\(c(pts[0].y)) "
            case .addQuadCurveToPoint:
                d += "Q\(c(pts[0].x)),\(c(pts[0].y)) \(c(pts[1].x)),\(c(pts[1].y)) "
            case .addCurveToPoint:
                d +=
                    "C\(c(pts[0].x)),\(c(pts[0].y)) "
                    + "\(c(pts[1].x)),\(c(pts[1].y)) "
                    + "\(c(pts[2].x)),\(c(pts[2].y)) "
            case .closeSubpath:
                d += "Z "
            @unknown default:
                break
            }
        }
        return d.trimmingCharacters(in: .whitespaces)
    }

    private static func c(_ v: CGFloat) -> String { String(format: "%.2f", v) }
}
