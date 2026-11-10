// Snap — a tiny menu bar screenshot tool.
// Press the shortcut (default ⇧⌘2), drag a region, annotate, then Copy / Save.

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var captureItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var session: CaptureSession?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ note: Notification) {
        setupStatusItem()
        HotKeyManager.shared.onPress = { [weak self] in self?.startCapture() }
        if !HotKeyManager.shared.register(Prefs.hotKey) {
            NSLog("Snap: couldn't register \(Prefs.hotKey.display)")
        }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snap")
        img?.isTemplate = true
        statusItem.button?.image = img

        let menu = NSMenu()
        menu.delegate = self
        captureItem = item("Capture Region", #selector(captureFromMenu))
        menu.addItem(captureItem)
        menu.addItem(item("Open Screenshots Folder", #selector(openFolder)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        loginItem = item("Open at Login", #selector(toggleLogin))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Snap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    func menuWillOpen(_ menu: NSMenu) {
        captureItem.title = "Capture Region  (\(Prefs.hotKey.display))"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func captureFromMenu() {
        // Let the menu close so it isn't in the shot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.startCapture() }
    }

    @objc private func openFolder() {
        let folder = Prefs.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func openSettings() {
        if settings == nil { settings = SettingsWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Snap: login item error: \(error)")
        }
    }

    // MARK: Capture

    func startCapture() {
        guard session == nil else { return }
        Task { @MainActor in
            do {
                let shots = try await captureAllScreens()
                guard !shots.isEmpty else { return }
                let s = CaptureSession(shots: shots) { [weak self] in self?.session = nil }
                self.session = s
                s.show()
            } catch {
                self.showPermissionAlert(error)
            }
        }
    }

    private func showPermissionAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Snap needs Screen Recording permission"
        alert.informativeText = "Enable Snap in System Settings → Privacy & Security → Screen & System Audio Recording, then try again.\n\n(\(error.localizedDescription))"
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
