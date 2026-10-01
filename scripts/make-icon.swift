import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "artifacts"
let iconset = "\(outDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(atPath: iconset)
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func draw(px: CGFloat) {
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * px, y: y * px, width: w * px, height: h * px)
    }

    // Red background squircle
    let inset = px * 0.045
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: inset, dy: inset),
                              xRadius: px * 0.22, yRadius: px * 0.22)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.97, green: 0.34, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.70, green: 0.06, blue: 0.05, alpha: 1)
    ])!.draw(in: bgPath, angle: -90)

    // Soft shadow behind the white bottle
    NSColor.black.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: r(0.343, 0.118, 0.335, 0.565), xRadius: px * 0.085, yRadius: px * 0.085).fill()

    // Bottle body (white)
    let body = NSBezierPath(roundedRect: r(0.335, 0.135, 0.33, 0.56), xRadius: px * 0.085, yRadius: px * 0.085)
    NSGradient(colors: [
        NSColor.white,
        NSColor(calibratedWhite: 0.88, alpha: 1)
    ])!.draw(in: body, angle: -90)

    // Neck (white)
    let neck = NSBezierPath(roundedRect: r(0.452, 0.665, 0.096, 0.105), xRadius: px * 0.02, yRadius: px * 0.02)
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    neck.fill()

    // Cap (light gray)
    let cap = NSBezierPath(roundedRect: r(0.432, 0.765, 0.136, 0.10), xRadius: px * 0.035, yRadius: px * 0.035)
    NSGradient(colors: [
        NSColor(calibratedWhite: 0.98, alpha: 1),
        NSColor(calibratedWhite: 0.78, alpha: 1)
    ])!.draw(in: cap, angle: -90)
    NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: 0.432 * px, y: 0.815 * px))
    seam.line(to: NSPoint(x: 0.568 * px, y: 0.815 * px))
    seam.lineWidth = px * 0.012
    seam.stroke()

    // Red label
    let label = NSBezierPath(roundedRect: r(0.365, 0.29, 0.27, 0.215), xRadius: px * 0.035, yRadius: px * 0.035)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.91, green: 0.25, blue: 0.19, alpha: 1),
        NSColor(calibratedRed: 0.72, green: 0.08, blue: 0.06, alpha: 1)
    ])!.draw(in: label, angle: -90)

    // White tomato on the label
    let tomatoRect = r(0.452, 0.375, 0.096, 0.096)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: tomatoRect).fill()
    // Green leaf
    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: 0.50 * px, y: 0.474 * px))
    leaf.line(to: NSPoint(x: 0.462 * px, y: 0.502 * px))
    leaf.line(to: NSPoint(x: 0.50 * px, y: 0.489 * px))
    leaf.line(to: NSPoint(x: 0.538 * px, y: 0.502 * px))
    leaf.close()
    NSColor(calibratedRed: 0.22, green: 0.54, blue: 0.20, alpha: 1).setFill()
    leaf.fill()
    // Tomato highlight
    NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
    NSBezierPath(ovalIn: r(0.466, 0.437, 0.022, 0.020)).fill()

    // Label text lines
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: r(0.415, 0.345, 0.17, 0.017), xRadius: px * 0.008, yRadius: px * 0.008).fill()
    NSBezierPath(roundedRect: r(0.44, 0.315, 0.12, 0.017), xRadius: px * 0.008, yRadius: px * 0.008).fill()

    // Subtle right-side shading on the white bottle
    NSColor.black.withAlphaComponent(0.06).setFill()
    NSBezierPath(roundedRect: r(0.60, 0.18, 0.055, 0.46), xRadius: px * 0.025, yRadius: px * 0.025).fill()
}

func render(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(px: CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, px) in entries {
    if let data = render(px: px) {
        try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
try? process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "icon ok" : "icon failed")
