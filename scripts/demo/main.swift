// Renders docs/screenshot.png for the README using Snap's real overlay + toolbar code
// over a made-up sample window. Run: ./scripts/make-demo.sh
import AppKit

let W: CGFloat = 1100, H: CGFloat = 680, SCALE: CGFloat = 2

func render(_ view: NSView) -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * SCALE),
                               pixelsHigh: Int(view.bounds.height * SCALE), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// A fake desktop with a "Sales Dashboard" window, drawn in flipped coordinates.
final class SceneView: NSView {
    override var isFlipped: Bool { true }

    func text(_ s: String, _ p: NSPoint, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .black) {
        (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }

    override func draw(_ r: NSRect) {
        NSGradient(colors: [NSColor(srgbRed: 0.18, green: 0.55, blue: 0.62, alpha: 1),
                            NSColor(srgbRed: 0.42, green: 0.30, blue: 0.70, alpha: 1)])!.draw(in: bounds, angle: 35)

        // Window
        let win = NSRect(x: 70, y: 50, width: 960, height: 580)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
        sh.shadowBlurRadius = 30
        sh.shadowOffset = NSSize(width: 0, height: -12)
        sh.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: win, xRadius: 12, yRadius: 12).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: win, xRadius: 12, yRadius: 12).addClip()
        NSColor(white: 0.95, alpha: 1).setFill()
        NSRect(x: win.minX, y: win.minY, width: win.width, height: 40).fill()
        NSGraphicsContext.restoreGraphicsState()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: win.minX + 16 + CGFloat(i) * 20, y: win.minY + 14, width: 12, height: 12)).fill()
        }
        text("Sales Dashboard", NSPoint(x: win.midX - 55, y: win.minY + 11), 13, .semibold, .darkGray)

        // Chart
        text("Monthly revenue", NSPoint(x: 100, y: 112), 22, .semibold)
        text("Jan – Aug 2026", NSPoint(x: 100, y: 142), 13, .regular, .gray)
        let baseline: CGFloat = 520
        NSColor(white: 0.9, alpha: 1).setFill()
        for i in 0...4 { NSRect(x: 100, y: baseline - CGFloat(i) * 75, width: 540, height: 1).fill() }
        let values: [CGFloat] = [120, 165, 140, 210, 185, 260, 230, 300]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug"]
        for (i, v) in values.enumerated() {
            let x = 112 + CGFloat(i) * 66
            NSColor(srgbRed: 0.27, green: 0.47, blue: 0.95, alpha: i == 7 ? 1 : 0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: baseline - v, width: 44, height: v), xRadius: 5, yRadius: 5).fill()
            text(months[i], NSPoint(x: x + 9, y: baseline + 8), 12, .regular, .gray)
        }

        // Stat cards
        let cards = [("Revenue", "$48.2k", "+12.4%"), ("Orders", "1,284", "+8.1%"), ("Conversion", "3.6%", "+0.9%")]
        for (i, c) in cards.enumerated() {
            let card = NSRect(x: 690, y: 112 + CGFloat(i) * 130, width: 300, height: 110)
            NSColor(white: 0.965, alpha: 1).setFill()
            NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()
            text(c.0, NSPoint(x: card.minX + 20, y: card.minY + 16), 13, .medium, .gray)
            text(c.1, NSPoint(x: card.minX + 20, y: card.minY + 38), 32, .bold)
            text(c.2, NSPoint(x: card.minX + 210, y: card.minY + 52), 14, .semibold, .systemGreen)
        }

        // Placeholder text lines below
        NSColor(white: 0.9, alpha: 1).setFill()
        for (i, w) in [520.0, 460.0, 300.0].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: 100, y: 568 + CGFloat(i) * 18, width: w, height: 8), xRadius: 4, yRadius: 4).fill()
        }
    }
}

_ = NSApplication.shared
NSApp.appearance = NSAppearance(named: .aqua)

let scene = SceneView(frame: NSRect(x: 0, y: 0, width: W, height: H))
let background = render(scene).cgImage!

let overlay = OverlayView(shot: ScreenShot(frame: scene.frame, image: background))
overlay.appearance = NSAppearance(named: .aqua)
overlay.loadDemo(
    selection: NSRect(x: 88, y: 100, width: 924, height: 458),
    annotations: [
        Annotation(tool: .arrow, start: NSPoint(x: 420, y: 168), end: NSPoint(x: 578, y: 212), color: palette[0]),
        Annotation(tool: .ellipse, start: NSPoint(x: 702, y: 408), end: NSPoint(x: 850, y: 462), color: palette[0]),
        Annotation(tool: .rect, start: NSPoint(x: 682, y: 104), end: NSPoint(x: 998, y: 230), color: palette[3]),
    ],
    tool: .arrow, colorIndex: 0)

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try! render(overlay).representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
