// Generates Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024  // design on a 1024 grid

    // Squircle body with drop shadow (macOS icon grid: 824pt body, 100pt margin).
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 22 * s
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.55, blue: 1.00, alpha: 1),
                        NSColor(srgbRed: 0.20, green: 0.24, blue: 0.85, alpha: 1)])!
        .draw(in: body, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Viewfinder corner brackets.
    let inset: CGFloat = 255 * s, arm: CGFloat = 130 * s
    let lo = inset, hi = size - inset
    let brackets = NSBezierPath()
    for (x, y, dx, dy) in [(lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0), (lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0)] {
        brackets.move(to: NSPoint(x: x, y: y + dy * arm))
        brackets.line(to: NSPoint(x: x, y: y))
        brackets.line(to: NSPoint(x: x + dx * arm, y: y))
    }
    brackets.lineWidth = 58 * s
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    NSColor.white.setStroke()
    brackets.stroke()

    // Annotation arrow pointing into the frame.
    let coral = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.36, alpha: 1)
    let start = NSPoint(x: 395 * s, y: 395 * s), end = NSPoint(x: 640 * s, y: 640 * s)
    let ux = (end.x - start.x) / hypot(end.x - start.x, end.y - start.y), uy = ux
    let head: CGFloat = 125 * s, half: CGFloat = 78 * s
    let base = NSPoint(x: end.x - ux * head, y: end.y - uy * head)
    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.line(to: NSPoint(x: base.x + ux * 4 * s, y: base.y + uy * 4 * s))
    shaft.lineWidth = 50 * s
    shaft.lineCapStyle = .round
    coral.setStroke()
    shaft.stroke()
    let tip = NSBezierPath()
    tip.move(to: end)
    tip.line(to: NSPoint(x: base.x - uy * half, y: base.y + ux * half))
    tip.line(to: NSPoint(x: base.x + uy * half, y: base.y - ux * half))
    tip.close()
    tip.lineJoinStyle = .round
    tip.lineWidth = 14 * s
    coral.setFill()
    tip.fill()
    tip.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
try! drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
