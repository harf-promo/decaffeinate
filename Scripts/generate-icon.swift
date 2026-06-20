#!/usr/bin/env swift
import AppKit

// Renders the Decaffeinate app icon: a "decaffeinated" mug (with a Zzz) on a
// warm gradient, then assembles an .icns. Run from the repo root:
//     swift Scripts/generate-icon.swift
// Output: assets/AppIcon.icns and assets/icon-1024.png

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Rounded-rect background with a warm coffee gradient.
    let corner = size * 0.2237 // Apple's "squircle"-ish corner ratio
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    path.addClip()
    let colors = [
        NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.13, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.20, green: 0.12, blue: 0.07, alpha: 1).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: size, y: 0),
                               options: [])
    }

    // The mug, drawn from an SF Symbol in cream white.
    let cream = NSColor(calibratedRed: 0.97, green: 0.93, blue: 0.86, alpha: 1)
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .regular)
        .applying(.init(paletteColors: [cream]))
    if let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        let scale = (size * 0.5) / max(s.width, s.height)
        let drawSize = NSSize(width: s.width * scale, height: s.height * scale)
        let origin = NSPoint(x: (size - drawSize.width) / 2,
                             y: (size - drawSize.height) / 2 - size * 0.03)
        symbol.draw(in: NSRect(origin: origin, size: drawSize))
    }

    // A rising "z z z" to signal sleep — Decaffeinate's whole point.
    let zzzPlacements: [(x: CGFloat, y: CGFloat, fontScale: CGFloat)] = [
        (0.62, 0.66, 0.10), (0.70, 0.74, 0.13), (0.78, 0.83, 0.16)
    ]
    for placement in zzzPlacements {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * placement.fontScale, weight: .heavy),
            .foregroundColor: cream.withAlphaComponent(0.92)
        ]
        ("z" as NSString).draw(at: NSPoint(x: size * placement.x, y: size * placement.y),
                               withAttributes: attributes)
    }

    return image
}

func png(_ image: NSImage, size: CGFloat) -> Data? {
    let target = NSImage(size: NSSize(width: size, height: size))
    target.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    target.unlockFocus()
    guard let tiff = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
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
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
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
