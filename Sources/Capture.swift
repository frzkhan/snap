import AppKit
import ScreenCaptureKit

struct ScreenShot {
    let frame: NSRect   // the screen's frame in global coordinates
    let image: CGImage
}

@MainActor
func captureAllScreens() async throws -> [ScreenShot] {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    var result: [ScreenShot] = []
    for screen in NSScreen.screens {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == num.uint32Value }) else { continue }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * screen.backingScaleFactor)
        config.height = Int(screen.frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        config.captureResolution = .best
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        result.append(ScreenShot(frame: screen.frame, image: img))
    }
    return result
}

/// One overlay window per screen; lives from hotkey press until copy/save/cancel.
final class CaptureSession {
    private var windows: [OverlayWindow] = []
    private let onEnd: () -> Void

    init(shots: [ScreenShot], onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        for shot in shots {
            let w = OverlayWindow(shot: shot)
            w.overlay.session = self
            windows.append(w)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        for w in windows { w.orderFrontRegardless() }
        let target = windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first
        target?.makeKey()
        target?.makeFirstResponder(target?.overlay)
    }

    /// A drag started on one screen: clear selections on the others.
    func selectionStarted(in view: OverlayView) {
        for w in windows where w.overlay !== view { w.overlay.clearSelection() }
        view.window?.makeKey()
    }

    func end() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        onEnd()
    }

    func copy(_ image: CGImage) {
        end()
        let rep = NSBitmapImageRep(cgImage: image)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) { pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        Toast.show("Copied to clipboard")
    }

    /// Saves straight into the folder chosen in Settings (no dialog).
    func save(_ image: CGImage) {
        end()
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        let folder = Prefs.saveFolder
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = fmt.string(from: Date())
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var url = folder.appendingPathComponent("Screenshot \(stamp).png")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("Screenshot \(stamp) (\(n)).png")
                n += 1
            }
            try png.write(to: url)
            Toast.show("Saved to \(folder.lastPathComponent)")
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't save screenshot to \(folder.path)"
            alert.runModal()
        }
    }
}

/// Small self-dismissing HUD at the bottom of the active screen.
enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        let ts = label.fittingSize
        let size = NSSize(width: ts.width + 28, height: ts.height + 16)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 80)

        let p = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        bg.layer?.cornerRadius = 8
        label.frame = NSRect(x: 14, y: 8, width: ts.width, height: ts.height)
        bg.addSubview(label)
        p.contentView = bg
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if panel === p { p.orderOut(nil); panel = nil }
        }
    }
}
