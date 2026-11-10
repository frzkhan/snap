import AppKit
import Carbon.HIToolbox

// MARK: - Stored preferences

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon modifier mask (cmdKey, shiftKey, …)
    var display: String

    static let defaultKey = HotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), display: "⇧⌘2")
}

enum Prefs {
    private static let d = UserDefaults.standard

    static var hotKey: HotKey {
        get {
            if let data = d.data(forKey: "hotKey"), let hk = try? JSONDecoder().decode(HotKey.self, from: data) { return hk }
            return .defaultKey
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "hotKey") }
    }

    static var saveFolder: URL {
        get {
            if let p = d.string(forKey: "saveFolder") { return URL(fileURLWithPath: p, isDirectory: true) }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { d.set(newValue.path, forKey: "saveFolder") }
    }
}

// MARK: - Global hotkey (Carbon — needs no Accessibility permission)

final class HotKeyManager {
    static let shared = HotKeyManager()
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    @discardableResult
    func register(_ hk: HotKey) -> Bool {
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x534E4150) /* 'SNAP' */, id: 1)
        return RegisterEventHotKey(hk.keyCode, hk.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }
}

// MARK: - Shortcut recorder control

private let functionKeys: [Int: String] = {
    let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                 kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
    var m: [Int: String] = [:]
    for (i, c) in codes.enumerated() { m[c] = "F\(i + 1)" }
    return m
}()

private let specialKeys: [Int: String] = [
    kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
]

final class ShortcutRecorder: NSButton {
    var hotKey: HotKey { didSet { updateTitle() } }
    var onChange: ((HotKey) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            updateTitle()
            onRecordingChange?(isRecording)
        }
    }

    init(hotKey: HotKey) {
        self.hotKey = hotKey
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        updateTitle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateTitle() {
        title = isRecording ? "Type shortcut…" : hotKey.display
    }

    @objc private func startRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    func stopRecording() { isRecording = false }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { record(event) } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        if code == kVK_Escape && flags.isEmpty { isRecording = false; return }

        // Require ⌘/⌥/⌃ unless it's a function key, so plain typing isn't hijacked.
        let isFKey = functionKeys[code] != nil
        guard isFKey || !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return }

        var carbon: UInt32 = 0
        var display = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); display += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); display += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); display += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); display += "⌘" }
        display += functionKeys[code] ?? specialKeys[code]
            ?? (event.characters(byApplyingModifiers: []) ?? "?").uppercased()

        isRecording = false
        hotKey = HotKey(keyCode: UInt32(code), modifiers: carbon, display: display)
        onChange?(hotKey)
    }
}

// MARK: - Settings window

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let recorder = ShortcutRecorder(hotKey: Prefs.hotKey)
    private let pathControl = NSPathControl()

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 130),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Snap Settings"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self

        recorder.onRecordingChange = { recording in
            // Free the current hotkey while recording so it can be typed into the field.
            if recording { HotKeyManager.shared.unregister() } else { HotKeyManager.shared.register(Prefs.hotKey) }
        }
        recorder.onChange = { [weak self] hk in self?.apply(hk) }

        pathControl.url = Prefs.saveFolder
        pathControl.pathStyle = .standard
        pathControl.isEditable = false
        pathControl.translatesAutoresizingMaskIntoConstraints = false
        pathControl.widthAnchor.constraint(equalToConstant: 250).isActive = true

        let reset = NSButton(title: "Reset", target: self, action: #selector(resetShortcut))
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))

        let grid = NSGridView(views: [
            [label("Capture shortcut:"), NSStackView(views: [recorder, reset])],
            [label("Save screenshots to:"), NSStackView(views: [pathControl, choose])],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .none
        grid.yPlacement = .center
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
        ])
        w.contentView = content
        w.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private func apply(_ hk: HotKey) {
        let old = Prefs.hotKey
        Prefs.hotKey = hk
        if !HotKeyManager.shared.register(hk) {
            Prefs.hotKey = old
            HotKeyManager.shared.register(old)
            recorder.hotKey = old
            let alert = NSAlert()
            alert.messageText = "\(hk.display) can't be used"
            alert.informativeText = "That shortcut is reserved or already taken. Try a different combination."
            alert.beginSheetModal(for: window!)
        }
    }

    @objc private func resetShortcut() {
        recorder.stopRecording()
        recorder.hotKey = .defaultKey
        apply(.defaultKey)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Prefs.saveFolder
        panel.prompt = "Choose"
        panel.beginSheetModal(for: window!) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Prefs.saveFolder = url
            self?.pathControl.url = url
        }
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stopRecording()
        window?.makeFirstResponder(nil)
    }
}
