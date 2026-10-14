import UniformTypeIdentifiers
import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyManager()
    private var editors: [EditorWindowController] = []
    private var failedHotKeys: [String] = []
    private var thumbnail: ThumbnailPanel?
    private lazy var startWindow: StartWindowController = {
        let w = StartWindowController()
        w.onOpen = { [weak self] url in self?.openFile(url) }
        return w
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched as a login item? Then stay in the menu bar.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        registerHotKeys()
        buildStatusItem()

        // Ask for Screen Recording once. Without it, captures show only the desktop.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        // Debug: SNAPMARK_OPEN=<png path> opens the editor on that image at launch.
        if let path = ProcessInfo.processInfo.environment["SNAPMARK_OPEN"],
           let image = NSImage(contentsOfFile: path) {
            openEditor(image)
        }
        // Debug: SNAPMARK_CAPTURE=1 takes a full-screen capture at launch.
        if ProcessInfo.processInfo.environment["SNAPMARK_CAPTURE"] != nil {
            capture(.fullScreen)
        }

        // Show the start window on a direct launch, but not at login or when opened
        // with a file (files arrive just after launch, so check on the next turn).
        if !launchedAtLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.editors.isEmpty,
                      ProcessInfo.processInfo.environment["SNAPMARK_CAPTURE"] == nil else { return }
                self.showStartWindow()
            }
        }
    }

    /// Opening SnapMark again while it runs shows the start window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStartWindow()
        return false
    }

    @objc private func showStartWindow() {
        startWindow.present()
    }

    // MARK: Opening files

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openFile(url) }
    }

    private func openFile(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { NSSound.beep(); return }
        RecentImages.add(url)
        openEditor(image, fileURL: url)
    }

    @objc private func openImage() {
        // With the start window open, show the picker as a sheet on it.
        if startWindow.window?.isVisible == true {
            startWindow.present()
            startWindow.openPanel()
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { openFile(url) }
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        let mods = cmdKey | shiftKey
        let keys: [(Int, String, CaptureMode)] = [
            (kVK_ANSI_3, "⌘⇧3", .fullScreen),
            (kVK_ANSI_4, "⌘⇧4", .selection),
            (kVK_ANSI_5, "⌘⇧5", .toolbar),
        ]
        for (code, name, mode) in keys {
            let ok = hotKeys.register(keyCode: code, modifiers: mods) { [weak self] in
                self?.capture(mode)
            }
            if !ok { failedHotKeys.append(name) }
        }
    }

    // MARK: Capture

    private func capture(_ mode: CaptureMode) {
        Capture.run(mode) { [weak self] url in
            guard let self, let url, let image = NSImage(contentsOf: url) else { return }
            RecentImages.add(url)
            self.thumbnail?.dismiss()
            let thumb = ThumbnailPanel(image: image)
            thumb.onClick = { [weak self] in self?.openEditor(image, fileURL: url) }
            thumb.onDismissed = { [weak self, weak thumb] in
                if self?.thumbnail === thumb { self?.thumbnail = nil }
            }
            self.thumbnail = thumb
            thumb.show()
        }
    }

    private func openEditor(_ image: NSImage, fileURL: URL? = nil) {
        do {
            let editor = EditorWindowController(image: image, fileURL: fileURL)
            editor.onClosed = { [weak self] closed in
                self?.editors.removeAll { $0 === closed }
            }
            self.editors.append(editor)
            editor.present()
        }
    }

    @objc private func captureFullScreen() { capture(.fullScreen) }
    @objc private func captureSelection() { capture(.selection) }
    @objc private func captureToolbar() { capture(.toolbar) }

    // MARK: Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "SnapMark")

        let menu = NSMenu()
        menu.addItem(item("Capture Full Screen   ⌘⇧3", #selector(captureFullScreen)))
        menu.addItem(item("Capture Selection   ⌘⇧4", #selector(captureSelection)))
        menu.addItem(item("Capture with Toolbar   ⌘⇧5", #selector(captureToolbar)))
        menu.addItem(item("Open Image…", #selector(openImage)))
        menu.addItem(item("Show Start Window", #selector(showStartWindow)))
        menu.addItem(.separator())

        if !failedHotKeys.isEmpty {
            let warn = NSMenuItem(title: "Not active: \(failedHotKeys.joined(separator: ", ")) (see Keyboard Shortcuts)",
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(item("Open Keyboard Shortcuts Settings…", #selector(openShortcutSettings)))
        menu.addItem(item("Open Screen Recording Settings…", #selector(openScreenRecordingSettings)))

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SnapMark", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func openShortcutSettings() {
        open("x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")
    }

    @objc private func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("SnapMark: launch at login failed: \(error)")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
