import AppKit

/// One command in the ⌘K palette.
struct PaletteCommand {
    let name: String
    let aliases: [String]
    let shortcut: String
    let run: () -> Void

    /// Lower is better; nil means no match. Substring first, then in-order letters.
    func score(_ query: String) -> Int? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return 0 }
        var best: Int?
        for (i, word) in ([name] + aliases).map({ $0.lowercased() }).enumerated() {
            let penalty = i == 0 ? 0 : 1
            if word.hasPrefix(q) { best = min(best ?? .max, 0 + penalty) }
            else if word.contains(q) { best = min(best ?? .max, 10 + penalty) }
            else if Self.fuzzy(q, word) { best = min(best ?? .max, 20 + penalty) }
        }
        return best
    }

    private static func fuzzy(_ q: String, _ word: String) -> Bool {
        var it = word.makeIterator()
        return q.allSatisfy { c in
            while let w = it.next() { if w == c { return true } }
            return false
        }
    }
}

/// Spotlight-style search over editor commands, shown over the editor window.
/// Up/Down move, Return runs, Esc or a click outside closes.
final class CommandPalette: NSView, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onClose: (() -> Void)?
    private let commands: [PaletteCommand]
    private var matches: [PaletteCommand] = []
    private let panel = NSView()
    private let field = NSSearchField()
    private let table = NSTableView()
    private static let rowHeight: CGFloat = 30
    private static let maxRows = 8

    init(commands: [PaletteCommand]) {
        self.commands = commands
        super.init(frame: .zero)
        build()
        filter()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(in container: NSView) {
        frame = container.bounds
        autoresizingMask = [.width, .height]
        container.addSubview(self)
        window?.makeFirstResponder(field)
    }

    /// Fills the search field (debug and tests).
    func prefill(_ query: String) {
        field.stringValue = query
        filter()
    }

    func close() {
        removeFromSuperview()
        onClose?()
    }

    private func build() {
        // Solid white card with a thin border and soft shadow.
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.white.cgColor
        panel.layer?.cornerRadius = 10
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
        panel.layer?.shadowColor = NSColor.black.cgColor
        panel.layer?.shadowOpacity = 0.18
        panel.layer?.shadowRadius = 16
        panel.layer?.shadowOffset = CGSize(width: 0, height: -4)
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        field.placeholderString = "Search commands"
        field.font = .systemFont(ofSize: 16)
        field.focusRingType = .none
        field.delegate = self
        field.sendsSearchStringImmediately = true

        let column = NSTableColumn(identifier: .init("cmd"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.refusesFirstResponder = true

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true

        for v in [field, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(v)
        }
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor, constant: 90),
            panel.widthAnchor.constraint(equalToConstant: 420),
            field.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            field.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6),
            scroll.heightAnchor.constraint(equalToConstant: Self.rowHeight * CGFloat(Self.maxRows)),
        ])
    }

    // Click outside the panel closes it.
    override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { close() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()
    }

    private func filter() {
        let q = field.stringValue
        matches = commands.enumerated()
            .compactMap { i, c in c.score(q).map { (s: $0, i: i, c: c) } }
            .sorted { ($0.s, $0.i) < ($1.s, $1.i) }
            .map(\.c)
        table.reloadData()
        if !matches.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    private func runSelected() {
        let row = table.selectedRow
        guard matches.indices.contains(row) else { NSSound.beep(); return }
        let command = matches[row]
        close()
        command.run()
    }

    @objc private func rowClicked() {
        if table.clickedRow >= 0 { runSelected() }
    }

    // MARK: Search field

    func controlTextDidChange(_ obj: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): runSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)): close(); return true
        default: return false
        }
    }

    private func move(_ d: Int) {
        guard !matches.isEmpty else { return }
        let row = min(max(table.selectedRow + d, 0), matches.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = matches[row]
        let name = NSTextField(labelWithString: c.name)
        name.font = .systemFont(ofSize: 13)
        let key = NSTextField(labelWithString: c.shortcut)
        key.font = .systemFont(ofSize: 12)
        key.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [name, NSView(), key])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        return stack
    }
}
