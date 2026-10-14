import AppKit

/// One window per screenshot: a tool bar at the top and the canvas below.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: CanvasView
    private var undoButton: IconButton!
    private var redoButton: IconButton!
    private var toolButtons: [IconButton] = []
    private var swatchButtons: [NSButton] = []
    private let sizeLabel = Pill.label("")
    private let zoomLabel = Pill.label("100%", weight: .medium)
    private static let barHeight: CGFloat = 52
    /// The Desktop file this screenshot was saved to; ⌘S and Return overwrite it.
    private let fileURL: URL?
    var onClosed: ((EditorWindowController) -> Void)?

    init(image: NSImage, fileURL: URL? = nil) {
        self.fileURL = fileURL
        canvas = CanvasView(image: image)

        let window = NSWindow(contentRect: EditorWindowController.initialFrame(for: image.size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "SnapMark"
        // One unified 52 pt bar: an empty unified toolbar centers the traffic lights in it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let toolbar = NSToolbar(identifier: "SnapMarkEditor")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .white
        window.minSize = NSSize(width: 760, height: 360)
        super.init(window: window)
        window.delegate = self
        buildLayout()
        wireCanvas()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        fitWindowToImage()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        // Debug hooks for README screenshots.
        let env = ProcessInfo.processInfo.environment
        if env["SNAPMARK_DEMO"] != nil { canvas.addDemoMarkup() }
        if let q = env["SNAPMARK_PALETTE"] { showCommandPalette(); commandPalette?.prefill(q) }
    }

    // MARK: Setup

    /// Sizes the window so the image shows at actual size (1 image point = 1 screen
    /// point) when it fits on screen, measuring the real height of the tool bar.
    private func fitWindowToImage() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let chrome = content.bounds.height - canvas.bounds.height  // the bar
        let pad = CanvasView.padding
        let screen = (window.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = canvas.image.size
        let w = min(max(window.minSize.width, size.width + pad.left + pad.right), screen.width)
        let h = min(max(window.minSize.height, size.height + pad.top + pad.bottom + chrome), screen.height)
        window.setContentSize(NSSize(width: w, height: h))
        window.center()
    }

    private static func initialFrame(for imageSize: NSSize) -> NSRect {
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let barHeight: CGFloat = 80
        let maxW = screen.width * 0.85, maxH = screen.height * 0.85 - barHeight
        let scale = min(1, maxW / imageSize.width, maxH / imageSize.height)
        let w = max(640, imageSize.width * scale + 32)
        let h = max(320, imageSize.height * scale + 32 + barHeight)
        return NSRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h)
    }

    private func buildLayout() {
        guard let content = window?.contentView else { return }

        // Tools as icons; the selected one is filled with the accent color.
        toolButtons = Tool.allCases.map { t in
            let b = IconButton(symbol: t.symbol, tooltip: t.label, target: self, action: #selector(toolClicked(_:)))
            b.tag = t.rawValue
            return b
        }
        let rotate = ButtonGroup([
            IconButton(symbol: "rotate.left", tooltip: "Rotate Left (⇧⌘R)", target: self, action: #selector(rotateLeft)),
            IconButton(symbol: "rotate.right", tooltip: "Rotate Right (⌘R)", target: self, action: #selector(rotateRight)),
        ])
        undoButton = IconButton(symbol: "arrow.uturn.backward", tooltip: "Undo (⌘Z)", target: self, action: #selector(undoClicked))
        redoButton = IconButton(symbol: "arrow.uturn.forward", tooltip: "Redo (⇧⌘Z)", target: self, action: #selector(redoClicked))
        undoButton.isEnabled = false
        redoButton.isEnabled = false

        swatchButtons = palette.indices.map { i in
            let b = NSButton(image: NSImage(), target: self, action: #selector(swatchClicked(_:)))
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.refusesFirstResponder = true
            b.tag = i
            b.toolTip = ["Red", "Yellow", "Green", "Blue", "Black", "White"][safe: i]
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 22).isActive = true
            b.heightAnchor.constraint(equalToConstant: 22).isActive = true
            return b
        }
        let swatches = NSStackView(views: swatchButtons)
        swatches.spacing = 4

        let save = ActionButton(title: "Save", symbol: "arrow.down.to.line", primary: false,
                                tooltip: "Save (⌘S)", target: self, action: #selector(saveClicked))
        let copy = ActionButton(title: "Copy", symbol: "doc.on.doc", primary: true,
                                tooltip: "Copy (⌘C)", target: self, action: #selector(copyClicked))

        let row = NSStackView(views: [ButtonGroup(toolButtons), rotate, ButtonGroup([undoButton, redoButton]),
                                      NSView(), swatches, save, copy])
        row.orientation = .horizontal
        row.spacing = 10
        row.setCustomSpacing(12, after: swatches)
        row.setCustomSpacing(8, after: save)

        // Bar: translucent #F6F6F8 with a hairline bottom border.
        let bar = NSVisualEffectView()
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(srgbRed: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF8 / 255, alpha: 0.92).cgColor
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Chrome.border.cgColor

        // Footer pills.
        let commands = Pill([Pill.label("⌘K", weight: .semibold), Pill.label("Commands")])
        commands.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(commandsClicked)))
        commands.toolTip = "Search commands (⌘K)"
        let divider = Pill.label("|", color: Chrome.border)
        let zoomPill = Pill([sizeLabel, divider,
                             Pill.textButton("−", target: self, action: #selector(zoomOutClicked)),
                             zoomLabel,
                             Pill.textButton("+", target: self, action: #selector(zoomInClicked)),
                             Pill.textButton("Fit", target: self, action: #selector(fitClicked))])

        for v in [canvas, bar, tint, line, row, commands, zoomPill] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        let h = Self.barHeight
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: h),
            tint.topAnchor.constraint(equalTo: bar.topAnchor),
            tint.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 84),  // after the traffic lights
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            canvas.topAnchor.constraint(equalTo: bar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            commands.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            commands.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            zoomPill.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            zoomPill.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        refreshTools()
        refreshSwatches()
        refreshFooter()
    }

    private func refreshTools() {
        for b in toolButtons { b.isSelected = b.tag == canvas.tool.rawValue }
    }

    private func refreshSwatches() {
        for b in swatchButtons {
            b.image = Self.swatch(palette[b.tag], selected: b.tag == canvas.colorIndex)
        }
    }

    /// "W × H px" of the current image and the live zoom.
    private func refreshFooter() {
        let image = canvas.image
        let px = image.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
        sizeLabel.stringValue = "\(Int(px.width)) × \(Int(px.height)) px"
        zoomLabel.stringValue = "\(Int((canvas.displayScale * 100).rounded()))%"
    }

    private static func swatch(_ color: NSColor, selected: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            if selected {
                NSColor.controlAccentColor.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 2
                ring.stroke()
            }
            color.setFill()
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
            dot.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            dot.lineWidth = 0.5
            dot.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func wireCanvas() {
        canvas.onToolChange = { [weak self] _ in self?.refreshTools() }
        canvas.onColorChange = { [weak self] _ in self?.refreshSwatches() }
        canvas.onViewChange = { [weak self] in self?.refreshFooter() }
        canvas.onCopy = { [weak self] in self?.copyToClipboard() }
        canvas.onSave = { [weak self] in self?.saveToDisk() }
        canvas.onClose = { [weak self] in self?.close() }
        canvas.onCommandPalette = { [weak self] in self?.showCommandPalette() }
        canvas.onHistoryChange = { [weak self] in
            guard let self else { return }
            self.undoButton.isEnabled = self.canvas.canUndo
            self.redoButton.isEnabled = self.canvas.canRedo
        }
    }

    // MARK: Command palette

    private var commandPalette: CommandPalette?

    private func showCommandPalette() {
        guard commandPalette == nil, let content = window?.contentView else { return }
        let c = canvas
        func tool(_ t: Tool, _ aliases: [String]) -> PaletteCommand {
            PaletteCommand(name: t.label.components(separatedBy: " (").first ?? t.label, aliases: aliases,
                           shortcut: t.key.uppercased()) { [weak self] in self?.selectTool(t) }
        }
        let colorNames = ["Red", "Yellow", "Green", "Blue", "Black", "White"]
        var commands: [PaletteCommand] = [
            tool(.crop, ["trim", "cut"]),
            tool(.arrow, ["pointer", "line"]),
            tool(.rectangle, ["box", "square", "shape"]),
            tool(.blackout, ["redact", "censor", "hide", "confidential", "black box"]),
            tool(.pen, ["draw", "pencil", "freehand"]),
            tool(.text, ["caption", "label", "type"]),
            tool(.step, ["number", "badge", "counter"]),
        ]
        for (i, name) in colorNames.enumerated() where i < SnapMark.palette.count {
            commands.append(PaletteCommand(name: name, aliases: ["color", "colour"], shortcut: "") { [weak self] in
                c.colorIndex = i; self?.window?.makeFirstResponder(c)
            })
        }
        commands += [
            PaletteCommand(name: "Rotate Right", aliases: ["clockwise", "turn"], shortcut: "⌘R") { c.rotate(clockwise: true) },
            PaletteCommand(name: "Rotate Left", aliases: ["counterclockwise", "anticlockwise", "turn"], shortcut: "⇧⌘R") { c.rotate(clockwise: false) },
            PaletteCommand(name: "Undo", aliases: ["revert", "back"], shortcut: "⌘Z") { c.undo() },
            PaletteCommand(name: "Redo", aliases: ["again", "forward"], shortcut: "⇧⌘Z") { c.redo() },
            PaletteCommand(name: "Copy", aliases: ["clipboard"], shortcut: "⌘C") { [weak self] in self?.copyToClipboard() },
            PaletteCommand(name: "Save", aliases: ["write", "export"], shortcut: "⌘S") { [weak self] in self?.saveToDisk() },
            PaletteCommand(name: "Zoom to Fit", aliases: ["fit", "reset zoom"], shortcut: "⌘0") { c.resetZoom() },
            PaletteCommand(name: "Zoom In", aliases: ["magnify", "bigger"], shortcut: "⌘+") { c.zoom(by: 1.5) },
            PaletteCommand(name: "Zoom Out", aliases: ["smaller"], shortcut: "⌘−") { c.zoom(by: 1 / 1.5) },
            PaletteCommand(name: "Actual Size", aliases: ["100%", "1:1", "zoom"], shortcut: "") { c.actualSize() },
            PaletteCommand(name: "Close", aliases: ["quit", "exit", "dismiss"], shortcut: "⌘W") { [weak self] in self?.close() },
        ]
        let p = CommandPalette(commands: commands)
        p.onClose = { [weak self] in
            self?.commandPalette = nil
            if self?.window?.firstResponder !== c { self?.window?.makeFirstResponder(c) }
        }
        commandPalette = p
        p.show(in: content)
    }

    private func selectTool(_ t: Tool) {
        canvas.tool = t
        window?.makeFirstResponder(canvas)
    }

    @objc private func undoClicked() { canvas.undo(); window?.makeFirstResponder(canvas) }
    @objc private func redoClicked() { canvas.redo(); window?.makeFirstResponder(canvas) }

    @objc private func rotateLeft() { canvas.rotate(clockwise: false); window?.makeFirstResponder(canvas) }
    @objc private func rotateRight() { canvas.rotate(clockwise: true); window?.makeFirstResponder(canvas) }

    @objc private func toolClicked(_ sender: NSButton) {
        if let t = Tool(rawValue: sender.tag) { canvas.tool = t }
        window?.makeFirstResponder(canvas)
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        canvas.colorIndex = sender.tag
        window?.makeFirstResponder(canvas)
    }

    @objc private func saveClicked() { saveToDisk(); window?.makeFirstResponder(canvas) }
    @objc private func copyClicked() { copyToClipboard(); window?.makeFirstResponder(canvas) }
    @objc private func commandsClicked() { showCommandPalette() }
    @objc private func zoomInClicked() { canvas.zoom(by: 1.5); window?.makeFirstResponder(canvas) }
    @objc private func zoomOutClicked() { canvas.zoom(by: 1 / 1.5); window?.makeFirstResponder(canvas) }
    @objc private func fitClicked() { canvas.resetZoom(); window?.makeFirstResponder(canvas) }

    // MARK: Output

    private func pngData() -> Data? {
        canvas.flattened()?.representation(using: .png, properties: [:])
    }

    private func copyToClipboard() {
        guard let rep = canvas.flattened(), let png = rep.representation(using: .png, properties: [:]) else {
            NSSound.beep(); return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        pb.setData(png, forType: .png)
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    @discardableResult
    private func saveToDisk() -> URL? {
        guard let data = pngData() else { NSSound.beep(); return nil }
        let url = fileURL ?? SaveLocation.newFileURL()
        do {
            try data.write(to: url, options: .atomic)
            RecentImages.add(url)
            return url
        } catch {
            NSLog("SnapMark: save failed: \(error)")
            NSSound.beep()
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?(self)
    }
}

enum SaveLocation {
    static var folder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    static func newFileURL() -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let base = "Screenshot \(f.string(from: Date()))"
        var url = folder.appendingPathComponent(base + ".png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        return url
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
