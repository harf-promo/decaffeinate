#!/usr/bin/env swift
import AppKit

// Renders the Decaffeinate app icon — a crescent moon + a single green dot on a
// flat "night" field, in the Harf design language (no gradients; harf-grey mark
// + one harf-green accent). Then assembles an .icns. Run from the repo root:
//     swift Scripts/generate-icon.swift
// Output: assets/AppIcon.icns and assets/icon-1024.png

// Harf brand colours (sRGB).
let night = NSColor(srgbRed: 0x1A / 255.0, green: 0x1B / 255.0, blue: 0x1D / 255.0, alpha: 1)  // grey-900
let grey = NSColor(srgbRed: 0x93 / 255.0, green: 0x95 / 255.0, blue: 0x98 / 255.0, alpha: 1)  // harf-grey
let green = NSColor(srgbRed: 0xA4 / 255.0, green: 0xCD / 255.0, blue: 0x39 / 255.0, alpha: 1)  // harf-green

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Flat night field, clipped to the macOS squircle.
    let corner = size * 0.2237
    let clip = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    clip.addClip()
    night.setFill()
    clip.fill()

    // Crescent = a harf-grey disc with an offset night-coloured disc carved out
    // (set difference, not even-odd — crisp at every size).
    grey.setFill()
    circle(size * 0.50, size * 0.515, size * 0.300).fill()
    night.setFill()
    circle(size * 0.635, size * 0.605, size * 0.288).fill()

    // A single green dot — the "star" in the crescent's opening (green is
    // punctuation: one mark per surface).
    green.setFill()
    circle(size * 0.700, size * 0.300, size * 0.052).fill()

    return image
}

func png(_ image: NSImage, size: CGFloat) -> Data? {
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
