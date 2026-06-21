#!/usr/bin/env swift
import AppKit

// Renders the Decaffeinate app icon — the "nightcap": a flat geometric coffee
// cup (harf-grey) with a single harf-green crescent moon rising like steam, on a
// flat ink "night" field. Coffee is the app's domain; the crescent is the sleep
// it brings. No gradient. Then assembles an .icns. Run from the repo root:
//     swift Scripts/generate-icon.swift
// Output: assets/AppIcon.icns and assets/icon-1024.png

let night = NSColor(srgbRed: 0x1A / 255.0, green: 0x1B / 255.0, blue: 0x1D / 255.0, alpha: 1)  // grey-900
let grey = NSColor(srgbRed: 0x93 / 255.0, green: 0x95 / 255.0, blue: 0x98 / 255.0, alpha: 1)  // harf-grey
let green = NSColor(srgbRed: 0xA4 / 255.0, green: 0xCD / 255.0, blue: 0x39 / 255.0, alpha: 1)  // harf-green

func cupBody(_ s: CGFloat) -> NSBezierPath {
    // A tapered, rounded coffee cup, filled.
    let topY = s * 0.62, botY = s * 0.34
    let topHalf = s * 0.165, botHalf = s * 0.135
    let cx = s * 0.46
    let r = s * 0.05
    let p = NSBezierPath()
    p.move(to: CGPoint(x: cx - topHalf, y: topY))
    p.line(to: CGPoint(x: cx - botHalf, y: botY + r))
    p.appendArc(
        withCenter: CGPoint(x: cx - botHalf + r, y: botY + r), radius: r, startAngle: 180,
        endAngle: 270)
    p.line(to: CGPoint(x: cx + botHalf - r, y: botY))
    p.appendArc(
        withCenter: CGPoint(x: cx + botHalf - r, y: botY + r), radius: r, startAngle: 270,
        endAngle: 360)
    p.line(to: CGPoint(x: cx + topHalf, y: topY))
    p.close()
    return p
}

func crescent(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
    let r2 = r * 0.80
    let d = r - r2
    let path = NSBezierPath()
    path.appendOval(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    let ox = cx + d * 0.85, oy = cy + d * 0.5
    path.appendOval(in: CGRect(x: ox - r2, y: oy - r2, width: r2 * 2, height: r2 * 2))
    path.windingRule = .evenOdd
    return path
}

func renderIcon(size s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let corner = s * 0.2237
    let clip = NSBezierPath(
        roundedRect: CGRect(x: 0, y: 0, width: s, height: s), xRadius: corner, yRadius: corner)
    clip.addClip()
    night.setFill()
    clip.fill()

    let cx = s * 0.46
    grey.setStroke()
    grey.setFill()

    // Saucer.
    NSBezierPath(
        ovalIn: CGRect(x: cx - s * 0.225, y: s * 0.235, width: s * 0.45, height: s * 0.075)).fill()
    // Handle.
    let handle = NSBezierPath()
    handle.appendArc(
        withCenter: CGPoint(x: cx + s * 0.175, y: s * 0.475), radius: s * 0.10, startAngle: -80,
        endAngle: 80)
    handle.lineWidth = s * 0.055
    handle.lineCapStyle = .round
    handle.stroke()
    // Cup body.
    cupBody(s).fill()
    // Crescent (green) rising at the upper-right, like steam.
    green.setFill()
    crescent(cx + s * 0.16, s * 0.74, s * 0.075).fill()

    img.unlockFocus()
    return img
}

func png(_ image: NSImage, size: CGFloat) -> Data? {
    let target = NSImage(size: NSSize(width: size, height: size))
    target.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    target.unlockFocus()
    guard let tiff = target.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        return nil
    }
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let assets = "assets"
try? fm.createDirectory(atPath: assets, withIntermediateDirectories: true)
let iconset = "\(assets)/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let master = renderIcon(size: 1024)
if let data = png(master, size: 1024) {
    try? data.write(to: URL(fileURLWithPath: "\(assets)/icon-1024.png"))
}

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in variants {
    if let data = png(master, size: size) {
        try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "\(assets)/AppIcon.icns"]
try? task.run()
task.waitUntilExit()
try? fm.removeItem(atPath: iconset)
print("Wrote \(assets)/AppIcon.icns")
