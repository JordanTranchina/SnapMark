import AppKit
import UniformTypeIdentifiers

/// Shown when SnapMark is opened directly: recent images plus an Open button.
final class StartWindowController: NSWindowController {
    var onOpen: ((URL) -> Void)?

    private let grid = NSGridView()
    private let emptyLabel = NSTextField(labelWithString: "No recent images yet.")
    private static let columns = 4
    private static let tile = NSSize(width: 160, height: 100)

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SnapMark"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.backgroundColor = .white
        window.minSize = NSSize(width: 760, height: 360)
        super.init(window: window)
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        reload()
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildLayout() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Recent Images")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let open = NSButton(title: "Open Image…", target: self, action: #selector(openPanel))
        open.bezelStyle = .rounded
        open.keyEquivalent = "o"
        open.keyEquivalentModifierMask = .command

        let header = NSStackView(views: [title, NSView(), open])
        header.orientation = .horizontal

        grid.rowSpacing = 16
        grid.columnSpacing = 16
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(grid)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(emptyLabel)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = doc

        let hint = NSTextField(labelWithString:
            "Capture anytime: ⌘⇧3 full screen   ⌘⇧4 selection   ⌘⇧5 screenshot toolbar")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor

        for v in [header, scroll, hint] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: 740),
            hint.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            grid.topAnchor.constraint(equalTo: doc.topAnchor),
            grid.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            grid.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            emptyLabel.topAnchor.constraint(equalTo: doc.topAnchor, constant: 8),
            emptyLabel.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
        ])
    }

    private func reload() {
        while grid.numberOfRows > 0 { grid.removeRow(at: 0) }
        let urls = RecentImages.list()
        emptyLabel.isHidden = !urls.isEmpty
        let tiles = urls.map(makeTile)
        stride(from: 0, to: tiles.count, by: Self.columns).forEach { i in
            var row: [NSView] = Array(tiles[i..<min(i + Self.columns, tiles.count)])
            while row.count < Self.columns { row.append(NSGridCell.emptyContentView) }
            grid.addRow(with: row)
        }
    }

    private func makeTile(_ url: URL) -> NSView {
        let button = NSButton(image: NSImage(contentsOf: url) ?? NSImage(), target: self, action: #selector(tileClicked(_:)))
        button.imageScaling = .scaleProportionallyUpOrDown
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        button.identifier = NSUserInterfaceItemIdentifier(url.path)
        button.toolTip = url.path
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.tile.width),
            button.heightAnchor.constraint(equalToConstant: Self.tile.height),
        ])

        let name = NSTextField(labelWithString: url.deletingPathExtension().lastPathComponent)
        name.font = .systemFont(ofSize: 11, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        let date = NSTextField(labelWithString: RecentImages.modified(url)
            .formatted(date: .abbreviated, time: .shortened))
        date.font = .systemFont(ofSize: 10)
        date.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [button, name, date])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        name.widthAnchor.constraint(lessThanOrEqualToConstant: Self.tile.width).isActive = true
        return stack
    }

    @objc private func tileClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        onOpen?(URL(fileURLWithPath: path))
        close()
    }

    /// File picker as a sheet on this window. The window closes only after a pick.
    @objc func openPanel() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            let urls = panel.urls
            for url in urls { self.onOpen?(url) }
            self.close()
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
