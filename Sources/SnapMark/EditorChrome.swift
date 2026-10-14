import AppKit

/// Small building blocks for the editor's toolbar and floating footer.
enum Chrome {
    static let border = NSColor(srgbRed: 0xD2 / 255, green: 0xD2 / 255, blue: 0xD7 / 255, alpha: 1)
    static let blue = NSColor(srgbRed: 0, green: 0x71 / 255, blue: 0xE3 / 255, alpha: 1)
    static let text = NSColor(srgbRed: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)

    static func symbol(_ name: String, _ size: CGFloat = 14, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }
}

/// Icon button with a selected state: accent-blue fill and white icon.
final class IconButton: NSButton {
    var isSelected = false { didSet { refresh() } }
    private let symbolName: String

    init(symbol: String, tooltip: String, target: AnyObject?, action: Selector?) {
        symbolName = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 26))
        self.target = target
        self.action = action
        toolTip = tooltip
        isBordered = false
        imagePosition = .imageOnly
        refusesFirstResponder = true
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool { didSet { refresh() } }

    private func refresh() {
        let tint: NSColor = isSelected ? .white : (isEnabled ? Chrome.text : Chrome.text.withAlphaComponent(0.3))
        image = Chrome.symbol(symbolName, 14, weight: isSelected ? .semibold : .regular)?
            .tinted(tint)
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
    }
}

/// A rounded group of icon buttons (a "segment").
final class ButtonGroup: NSStackView {
    init(_ buttons: [NSView]) {
        super.init(frame: .zero)
        setViews(buttons, in: .leading)
        orientation = .horizontal
        spacing = 2
        edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = Chrome.border.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Text button with an icon, used for Save (white) and Copy (blue).
/// Draws its own content (icon, 6 pt gap, label) with 12 pt side padding.
final class ActionButton: NSButton {
    init(title: String, symbol: String, primary: Bool, tooltip: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        toolTip = tooltip
        isBordered = false
        self.title = ""
        refusesFirstResponder = true
        setAccessibilityLabel(title)

        let color: NSColor = primary ? .white : Chrome.text
        let icon = NSImageView(image: Chrome.symbol(symbol, 12, weight: .medium)?.tinted(color) ?? NSImage())
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: primary ? .semibold : .medium)
        label.textColor = color
        let content = NSStackView(views: [icon, label])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 6
        content.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = (primary ? Chrome.blue : .white).cgColor
        if !primary {
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor(srgbRed: 0xC8 / 255, green: 0xC8 / 255, blue: 0xCD / 255, alpha: 1).cgColor
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Clicks on the label or icon still press the button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }
}

/// Floating pill: white 90%, hairline border, fully round, small shadow.
final class Pill: NSStackView {
    init(_ views: [NSView]) {
        super.init(frame: .zero)
        setViews(views, in: .leading)
        orientation = .horizontal
        spacing = 6
        edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = Chrome.border.cgColor
        layer?.cornerRadius = 14
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func label(_ text: String, color: NSColor = Chrome.text, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12, weight: weight)
        l.textColor = color
        return l
    }

    static func textButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.isBordered = false
        b.refusesFirstResponder = true
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: Chrome.text,
        ])
        return b
    }
}

extension NSImage {
    /// A copy of a template image filled with `color`.
    func tinted(_ color: NSColor) -> NSImage {
        let out = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        out.isTemplate = false
        return out
    }
}
