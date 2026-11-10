import AppKit
import Carbon.HIToolbox

// MARK: - Annotations

enum Tool: Int, CaseIterable {
    case arrow, ellipse, rect

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .ellipse: return "circle"
        case .rect: return "rectangle"
        }
    }
    var tip: String {
        switch self {
        case .arrow: return "Arrow (A)"
        case .ellipse: return "Circle (O)"
        case .rect: return "Rectangle (R)"
        }
    }
}

let palette: [NSColor] = [
    NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1),  // red
    NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1),  // yellow
    NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),  // green
    NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1),  // blue
    NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),  // white
]

struct Annotation {
    var tool: Tool
    var start: NSPoint
    var end: NSPoint
    var color: NSColor
    static let lineWidth: CGFloat = 3

    var isTrivial: Bool { hypot(end.x - start.x, end.y - start.y) < 4 }

    /// Draws into the current NSGraphicsContext, in overlay (flipped, point) coordinates.
    func draw() {
        color.setStroke()
        color.setFill()
        let r = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                       width: abs(end.x - start.x), height: abs(end.y - start.y))
        switch tool {
        case .rect:
            let p = NSBezierPath(rect: r)
            p.lineWidth = Self.lineWidth
            p.lineJoinStyle = .round
            p.stroke()
        case .ellipse:
            let p = NSBezierPath(ovalIn: r)
            p.lineWidth = Self.lineWidth
            p.stroke()
        case .arrow:
            let dx = end.x - start.x, dy = end.y - start.y
            let len = hypot(dx, dy)
            guard len > 1 else { return }
            let ux = dx / len, uy = dy / len
            let head = min(max(Self.lineWidth * 5, 16), len)
            let half = head * 0.55
            let base = NSPoint(x: end.x - ux * head, y: end.y - uy * head)

            let shaft = NSBezierPath()
            shaft.move(to: start)
            shaft.line(to: NSPoint(x: base.x + ux, y: base.y + uy))
            shaft.lineWidth = Self.lineWidth
            shaft.lineCapStyle = .round
            shaft.stroke()

            let tip = NSBezierPath()
            tip.move(to: end)
            tip.line(to: NSPoint(x: base.x - uy * half, y: base.y + ux * half))
            tip.line(to: NSPoint(x: base.x + uy * half, y: base.y - ux * half))
            tip.close()
            tip.fill()
        }
    }
}

// MARK: - Overlay window

final class OverlayWindow: NSWindow {
    let overlay: OverlayView

    init(shot: ScreenShot) {
        overlay = OverlayView(shot: shot)
        super.init(contentRect: shot.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        contentView = overlay
        setFrame(shot.screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Toolbar pieces

/// Swallows clicks on its background so they don't start a new selection.
final class ToolbarView: NSStackView {
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

final class SwatchButton: NSButton {
    let color: NSColor
    var isChosen = false { didSet { needsDisplay = true } }

    init(color: NSColor, index: Int, target: AnyObject, action: Selector) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 24))
        isBordered = false
        title = ""
        tag = index
        self.target = target
        self.action = action
        refusesFirstResponder = true
        toolTip = "Color (\(index + 1))"
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSRect(x: bounds.midX - 7, y: bounds.midY - 7, width: 14, height: 14)
        if isChosen {
            NSColor.labelColor.setStroke()
            let ring = NSBezierPath(ovalIn: c.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        color.setFill()
        NSBezierPath(ovalIn: c).fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        let edge = NSBezierPath(ovalIn: c.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()
    }
}

// MARK: - Overlay view

final class OverlayView: NSView {
    weak var session: CaptureSession?
    private static var colorIndex = 0   // remembered between captures

    private let shot: ScreenShot
    private let nsImage: NSImage
    private var start: NSPoint?
    private var selection: NSRect?
    private var tool: Tool?
    private var annotations: [Annotation] = []
    private var drawing: Annotation?

    private var toolbar: ToolbarView?
    private var toolButtons: [Tool: NSButton] = [:]
    private var swatches: [SwatchButton] = []

    init(shot: ScreenShot) {
        self.shot = shot
        self.nsImage = NSImage(cgImage: shot.image, size: shot.screen.frame.size)
        super.init(frame: NSRect(origin: .zero, size: shot.screen.frame.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    func clearSelection() {
        selection = nil
        start = nil
        annotations.removeAll()
        drawing = nil
        removeToolbar()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        let dim = NSBezierPath(rect: bounds)
        if let sel = selection { dim.append(NSBezierPath(rect: sel)); dim.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        guard let sel = selection else {
            drawLabel("Drag to select  ·  Esc to cancel", centeredIn: bounds)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: sel).addClip()
        annotations.forEach { $0.draw() }
        drawing?.draw()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
        drawLabel("\(Int(sel.width)) × \(Int(sel.height))",
                  at: NSPoint(x: sel.minX, y: sel.minY > 26 ? sel.minY - 24 : sel.minY + 4))
    }

    private func labelAttrs(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white]
    }

    private func drawLabel(_ text: String, at p: NSPoint, fontSize: CGFloat = 11) {
        let attrs = labelAttrs(fontSize)
        let size = (text as NSString).size(withAttributes: attrs)
        let bg = NSRect(x: p.x, y: p.y, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: p.x + 6, y: p.y + 3), withAttributes: attrs)
    }

    private func drawLabel(_ text: String, centeredIn r: NSRect) {
        let size = (text as NSString).size(withAttributes: labelAttrs(15))
        drawLabel(text, at: NSPoint(x: r.midX - size.width / 2 - 6, y: r.midY - size.height / 2 - 3), fontSize: 15)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let t = tool, selection != nil {
            drawing = Annotation(tool: t, start: p, end: p, color: palette[Self.colorIndex])
            return
        }
        session?.selectionStarted(in: self)
        clearSelection()
        start = p
    }

    override func mouseDragged(with event: NSEvent) {
        var p = convert(event.locationInWindow, from: nil)
        if var d = drawing {
            if event.modifierFlags.contains(.shift) { p = constrained(from: d.start, to: p, tool: d.tool) }
            d.end = p
            drawing = d
            needsDisplay = true
            return
        }
        guard let s = start else { return }
        selection = NSRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let d = drawing {
            drawing = nil
            if !d.isTrivial { annotations.append(d) }
            needsDisplay = true
            return
        }
        start = nil
        guard let sel = selection, sel.width >= 3, sel.height >= 3 else {
            selection = nil
            needsDisplay = true
            return
        }
        showToolbar(for: sel)
    }

    /// Shift: square/circle for shapes, 45° snapping for arrows.
    private func constrained(from s: NSPoint, to p: NSPoint, tool: Tool) -> NSPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        if tool == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return NSPoint(x: s.x + cos(angle) * len, y: s.y + sin(angle) * len)
        }
        let side = max(abs(dx), abs(dy))
        return NSPoint(x: s.x + (dx < 0 ? -side : side), y: s.y + (dy < 0 ? -side : side))
    }

    // MARK: Toolbar

    private func removeToolbar() {
        toolbar?.removeFromSuperview()
        toolbar = nil
        toolButtons.removeAll()
        swatches.removeAll()
    }

    private func showToolbar(for sel: NSRect) {
        removeToolbar()
        var views: [NSView] = []
        for t in Tool.allCases {
            let b = makeButton(t.symbol, t.tip, #selector(toolClicked(_:)))
            b.tag = t.rawValue
            toolButtons[t] = b
            views.append(b)
        }
        swatches = palette.enumerated().map { SwatchButton(color: $1, index: $0, target: self, action: #selector(swatchClicked(_:))) }
        views += swatches
        let undo = makeButton("arrow.uturn.backward", "Undo (⌘Z)", #selector(undoAction))
        views.append(undo)
        views.append(makeButton("doc.on.doc", "Copy (⌘C / Return)", #selector(copyAction)))
        views.append(makeButton("square.and.arrow.down", "Save to folder (⌘S)", #selector(saveAction)))
        views.append(makeButton("xmark", "Cancel (Esc)", #selector(cancelAction)))

        let bar = ToolbarView(views: views)
        bar.spacing = 2
        bar.setCustomSpacing(10, after: toolButtons[.rect]!)
        bar.setCustomSpacing(10, after: swatches.last!)
        bar.setCustomSpacing(10, after: undo)
        bar.edgeInsets = NSEdgeInsets(top: 3, left: 5, bottom: 3, right: 5)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        bar.layer?.cornerRadius = 7
        bar.layer?.borderWidth = 0.5
        bar.layer?.borderColor = NSColor.separatorColor.cgColor

        let size = bar.fittingSize
        var x = sel.maxX - size.width
        var y = sel.maxY + 6                                           // below the selection
        if y + size.height > bounds.maxY - 4 { y = sel.minY - size.height - 6 }   // else above
        if y < bounds.minY + 4 { y = sel.maxY - size.height - 6 }      // else inside, bottom edge
        x = max(bounds.minX + 4, min(x, bounds.maxX - size.width - 4))
        y = max(bounds.minY + 4, min(y, bounds.maxY - size.height - 4))
        bar.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        addSubview(bar)
        toolbar = bar
        window?.invalidateCursorRects(for: self)
        updateToolbarState()
    }

    private func makeButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.isBordered = false
        b.toolTip = tip
        b.refusesFirstResponder = true
        b.wantsLayer = true
        b.layer?.cornerRadius = 5
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return b
    }

    private func updateToolbarState() {
        for (t, b) in toolButtons {
            let on = t == tool
            b.layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor : nil
            b.contentTintColor = on ? .controlAccentColor : nil
        }
        for s in swatches { s.isChosen = s.tag == Self.colorIndex }
    }

    private func setTool(_ t: Tool?) {
        guard selection != nil else { return }
        tool = (tool == t) ? nil : t
        updateToolbarState()
    }

    private func setColor(_ i: Int) {
        guard palette.indices.contains(i) else { return }
        Self.colorIndex = i
        if tool == nil { tool = .arrow }   // picking a color implies you want to draw
        updateToolbarState()
    }

    @objc private func toolClicked(_ sender: NSButton) { setTool(Tool(rawValue: sender.tag)) }
    @objc private func swatchClicked(_ sender: NSButton) { setColor(sender.tag) }
    @objc private func undoAction() { if annotations.popLast() != nil { needsDisplay = true } }
    @objc private func copyAction() { if let img = renderedImage() { session?.copy(img) } }
    @objc private func saveAction() { if let img = renderedImage() { session?.save(img) } }
    @objc private func cancelAction() { session?.end() }

    // MARK: Export

    /// Crops the frozen screenshot to the selection and burns in the annotations at full pixel resolution.
    private func renderedImage() -> CGImage? {
        guard let sel = selection else { return nil }
        let scale = CGFloat(shot.image.width) / bounds.width
        let pr = CGRect(x: sel.minX * scale, y: sel.minY * scale, width: sel.width * scale, height: sel.height * scale).integral
        guard let cropped = shot.image.cropping(to: pr) else { return nil }
        if annotations.isEmpty { return cropped }

        let w = cropped.width, h = cropped.height
        let space = cropped.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return cropped }

        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Map overlay (flipped, points) coords onto the bitmap.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -pr.minX / scale, y: -pr.minY / scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        annotations.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? cropped
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape: cancelAction(); return
        case kVK_Return, kVK_ANSI_KeypadEnter: copyAction(); return
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a": setTool(.arrow)
        case "o", "e": setTool(.ellipse)
        case "r": setTool(.rect)
        case "1", "2", "3", "4", "5": setColor(Int(event.charactersIgnoringModifiers!)! - 1)
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": undoAction(); return true
        case "c": copyAction(); return true
        case "s": saveAction(); return true
        case "w", "q": cancelAction(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
