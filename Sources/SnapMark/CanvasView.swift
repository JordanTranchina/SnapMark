import AppKit

/// Shows the screenshot and handles crop and markup with mouse and keyboard.
final class CanvasView: NSView, NSTextFieldDelegate {
    private(set) var image: NSImage
    private(set) var annotations: [Annotation] = []

    var tool: Tool = .arrow {
        didSet { commitText(); onToolChange?(tool); onColorChange?(colorIndex); needsDisplay = true }
    }
    /// Text and shapes keep separate colors: text defaults to black, shapes to red.
    private var shapeColorIndex = 0
    private var textColorIndex = palette.firstIndex(of: .black) ?? 0
    var colorIndex: Int {
        get { tool == .text ? textColorIndex : shapeColorIndex }
        set {
            if tool == .text { textColorIndex = newValue } else { shapeColorIndex = newValue }
            onColorChange?(newValue)
        }
    }
    var color: NSColor { palette[colorIndex] }

    var onToolChange: ((Tool) -> Void)?
    var onColorChange: ((Int) -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onCommandPalette: (() -> Void)?

    private var undoStack: [(NSImage, [Annotation])] = [] { didSet { onHistoryChange?() } }
    private var redoStack: [(NSImage, [Annotation])] = [] { didSet { onHistoryChange?() } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var onHistoryChange: (() -> Void)?
    private var current: Annotation?
    private var dragStart: CGPoint?
    private var cropRect: CGRect?
    private var textField: NSTextField?
    private var textPoint: CGPoint = .zero
    /// Index of the text item being edited, if the field is editing existing text.
    private var editingIndex: Int?
    private var textColor: NSColor = .red
    private var textLineWidth: CGFloat = 4

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Line width in image points, so markup looks the same on large and small captures.
    private var lineWidth: CGFloat {
        max(3, max(image.size.width, image.size.height) / 400)
    }

    // MARK: Layout

    /// Zoom relative to the fit scale (1 = fit), and pan offset in view points.
    private var zoom: CGFloat = 1
    private var pan: CGPoint = .zero
    private static let maxScale: CGFloat = 8

    /// Space around the image: room for the floating footer at the bottom.
    static let padding = NSEdgeInsets(top: 28, left: 28, bottom: 60, right: 28)

    /// The area the image is fitted into.
    private var area: CGRect {
        let p = Self.padding
        return CGRect(x: p.left, y: p.top, width: max(1, bounds.width - p.left - p.right),
                      height: max(1, bounds.height - p.top - p.bottom))
    }

    /// Current display scale in screen points per image point (1 = 100%).
    var displayScale: CGFloat { layout.scale }
    var onViewChange: (() -> Void)?

    /// Scale that fits the whole image in the view (never above 1:1).
    private var fitScale: CGFloat {
        let area = self.area
        return max(0.01, min(1, area.width / image.size.width, area.height / image.size.height))
    }

    /// Where the image sits in the view, and its display scale.
    private var layout: (origin: CGPoint, scale: CGFloat) {
        let scale = fitScale * zoom
        let w = image.size.width * scale, h = image.size.height * scale
        return (CGPoint(x: area.midX - w / 2 + pan.x, y: area.midY - h / 2 + pan.y), scale)
    }

    /// Keeps a zoomed image from being panned out of view.
    private func clampPan() {
        let s = fitScale * zoom
        let maxX = max(0, (image.size.width * s - area.width) / 2 + 28)
        let maxY = max(0, (image.size.height * s - area.height) / 2 + 28)
        pan = CGPoint(x: min(max(pan.x, -maxX), maxX), y: min(max(pan.y, -maxY), maxY))
    }

    /// Zooms around the view center by `factor`.
    func zoom(by factor: CGFloat) {
        setZoom(zoom * factor)
    }

    /// 1 image point = 1 screen point (pixel-for-pixel on the same display type).
    func actualSize() {
        setZoom(1 / fitScale)
    }

    private func setZoom(_ z: CGFloat) {
        if textField != nil { commitText() }
        let old = fitScale * zoom
        zoom = min(max(z, 1), Self.maxScale / fitScale)
        pan = CGPoint(x: pan.x * fitScale * zoom / old, y: pan.y * fitScale * zoom / old)
        clampPan()
        needsDisplay = true
    }

    func resetZoom() {
        zoom = 1
        pan = .zero
        needsDisplay = true
    }

    // MARK: Zoom and pan

    override func magnify(with event: NSEvent) {
        if textField != nil { commitText() }
        let p = convert(event.locationInWindow, from: nil)
        let (o, oldScale) = layout
        let anchor = CGPoint(x: (p.x - o.x) / oldScale, y: (p.y - o.y) / oldScale)  // image point under pointer
        zoom = min(max(zoom * (1 + event.magnification), 1), Self.maxScale / fitScale)
        // Keep the anchor point under the pointer.
        let s = fitScale * zoom
        let w = image.size.width * s, h = image.size.height * s
        pan = CGPoint(x: p.x - anchor.x * s - (area.midX - w / 2),
                      y: p.y - anchor.y * s - (area.midY - h / 2))
        clampPan()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard zoom > 1 else { return super.scrollWheel(with: event) }
        if textField != nil { commitText() }
        // View is flipped, so scrolling content down means positive y.
        pan.x += event.scrollingDeltaX
        pan.y += event.scrollingDeltaY
        clampPan()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        clampPan()
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let (o, s) = layout
        let x = (p.x - o.x) / s, y = (p.y - o.y) / s
        return CGPoint(x: min(max(x, 0), image.size.width), y: min(max(y, 0), image.size.height))
    }

    private func viewPoint(_ p: CGPoint) -> CGPoint {
        let (o, s) = layout
        return CGPoint(x: o.x + p.x * s, y: o.y + p.y * s)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Backdrop #EBF0F5 with a faint 18 pt dot grid.
        NSColor(srgbRed: 0xEB / 255, green: 0xF0 / 255, blue: 0xF5 / 255, alpha: 1).setFill()
        bounds.fill()
        NSColor(srgbRed: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 0.10).setFill()
        let spacing: CGFloat = 18
        var y = (dirtyRect.minY / spacing).rounded(.down) * spacing
        while y <= dirtyRect.maxY {
            var x = (dirtyRect.minX / spacing).rounded(.down) * spacing
            while x <= dirtyRect.maxX {
                CGRect(x: x, y: y, width: 1, height: 1).fill()
                x += spacing
            }
            y += spacing
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let (o, s) = layout

        ctx.saveGState()
        // Like Preview: when each image pixel covers one or more screen pixels, draw
        // pixels as-is (sharp, blocky when zoomed). Smooth only when shrinking.
        let px = window?.backingScaleFactor ?? 2
        let imagePixelsPerPoint = image.representations.first.map { CGFloat($0.pixelsWide) / image.size.width } ?? 1
        let screenPixelsPerImagePixel = s * px / max(imagePixelsPerPoint, 0.01)
        let quality: NSImageInterpolation = screenPixelsPerImagePixel >= 0.999 ? .none : .high
        ctx.interpolationQuality = quality == .none ? .none : .high
        NSGraphicsContext.current?.imageInterpolation = quality
        // Snap to whole device pixels so a 1:1 image isn't resampled.
        ctx.translateBy(x: (o.x * px).rounded() / px, y: (o.y * px).rounded() / px)
        ctx.scaleBy(x: s, y: s)
        var visible = annotations
        if let i = editingIndex, visible.indices.contains(i) { visible.remove(at: i) }
        // Display only: 4 pt rounded corners, a soft drop shadow and a faint outline.
        // The saved file stays square.
        let frame = CGRect(origin: .zero, size: image.size)
        let radius = 4 / s
        let rounded = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 0.28)
        shadow.shadowBlurRadius = 28  // shadows are in screen points
        shadow.shadowOffset = NSSize(width: 0, height: -18)  // negative is down
        shadow.set()
        NSColor.white.setFill()
        rounded.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        rounded.addClip()
        Renderer.draw(image: image, annotations: visible + (current.map { [$0] } ?? []))
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.08).setStroke()
        let edge = NSBezierPath(roundedRect: frame.insetBy(dx: -0.5 / s, dy: -0.5 / s), xRadius: radius, yRadius: radius)
        edge.lineWidth = 1 / s
        edge.stroke()

        if let r = cropRect {
            let dim = NSBezierPath(rect: CGRect(origin: .zero, size: image.size))
            dim.append(NSBezierPath(rect: r))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.5).setFill()
            dim.fill()
            let border = NSBezierPath(rect: r)
            border.lineWidth = 1 / s
            border.setLineDash([6 / s, 4 / s], count: 2, phase: 0)
            NSColor.white.setStroke()
            border.stroke()
        }
        ctx.restoreGState()
        if lastReported != (image.size, s) {
            lastReported = (image.size, s)
            DispatchQueue.main.async { [weak self] in self?.onViewChange?() }
        }
    }
    private var lastReported: (NSSize, CGFloat) = (.zero, 0)

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let p = imagePoint(event)
        // Double-click on text (any tool), or a click with the Text tool, edits that text.
        if event.clickCount == 2 || tool == .text, let i = textIndex(at: p) {
            current = nil
            cropRect = nil
            dragStart = nil
            editText(at: i)
            return
        }
        dragStart = p
        switch tool {
        case .crop: cropRect = CGRect(origin: p, size: .zero)
        case .arrow: current = Annotation(kind: .arrow(from: p, to: p), color: color, lineWidth: lineWidth)
        case .rectangle: current = Annotation(kind: .rectangle(CGRect(origin: p, size: .zero)), color: color, lineWidth: lineWidth)
        case .step: current = Annotation(kind: .step(p), color: color, lineWidth: lineWidth)
        case .blackout: current = Annotation(kind: .blackout(CGRect(origin: p, size: .zero)), color: .black, lineWidth: lineWidth)
        case .pen: current = Annotation(kind: .pen([p]), color: color, lineWidth: lineWidth)
        case .text: beginText(at: p)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = imagePoint(event)
        let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                          width: abs(p.x - start.x), height: abs(p.y - start.y))
        switch tool {
        case .crop: cropRect = rect
        case .arrow: current?.kind = .arrow(from: start, to: p)
        case .rectangle: current?.kind = .rectangle(rect)
        case .blackout: current?.kind = .blackout(rect)
        case .pen:
            if case .pen(var points)? = current?.kind {
                points.append(p)
                current?.kind = .pen(points)
            }
        case .text, .step: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; current = nil; cropRect = nil; needsDisplay = true }
        if tool == .crop, let r = cropRect, r.width >= 4, r.height >= 4 {
            applyCrop(r)
        } else if let a = current, !a.isEmpty {
            pushUndo()
            annotations.append(a)
        }
    }

    // MARK: Crop and undo

    private func applyCrop(_ r: CGRect) {
        guard let cropped = Renderer.crop(image, to: r.integral) else { return }
        pushUndo()
        image = cropped
        zoom = 1
        pan = .zero
        annotations = annotations.map { $0.offset(by: CGPoint(x: -r.integral.minX, y: -r.integral.minY)) }
    }

    /// Turns the image and its markup by 90°. One undo step.
    func rotate(clockwise: Bool) {
        if textField != nil { commitText() }
        guard let rotated = Renderer.rotate(image, clockwise: clockwise) else { NSSound.beep(); return }
        let w = image.size.width, h = image.size.height
        pushUndo()
        image = rotated
        // Image coordinates are y-down.
        annotations = annotations.map { a in
            a.mapped { clockwise ? CGPoint(x: h - $0.y, y: $0.x) : CGPoint(x: $0.y, y: w - $0.x) }
        }
        zoom = 1
        pan = .zero
        needsDisplay = true
    }

    /// Records the state before a change. Any new change clears redo.
    private func pushUndo() {
        undoStack.append((image, annotations))
        redoStack.removeAll()
    }

    func undo() {
        if textField != nil { commitText() }
        guard let last = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append((image, annotations))
        restore(last)
    }

    func redo() {
        if textField != nil { commitText() }
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append((image, annotations))
        restore(next)
    }

    private func restore(_ state: (NSImage, [Annotation])) {
        let last = state
        image = last.0
        annotations = last.1
        zoom = 1
        pan = .zero
        needsDisplay = true
    }

    // MARK: Text

    /// Topmost text item whose bounds contain the image point.
    private func textIndex(at p: CGPoint) -> Int? {
        annotations.indices.last { annotations[$0].captionBounds?.contains(p) == true }
    }

    private func editText(at i: Int) {
        guard case let .text(string, point) = annotations[i].kind else { return }
        editingIndex = i
        beginText(at: point, string: string, color: annotations[i].color, lineWidth: annotations[i].lineWidth)
        needsDisplay = true
    }

    private func beginText(at p: CGPoint, string: String = "", color: NSColor? = nil, lineWidth: CGFloat? = nil) {
        textPoint = p
        textColor = color ?? self.color
        textLineWidth = lineWidth ?? self.lineWidth
        let s = layout.scale
        let field = NSTextField(string: string)
        // Looks like the finished caption: same font size, colors and box.
        let caption = Annotation(kind: .text("", at: p), color: textColor, lineWidth: textLineWidth)
        field.font = .systemFont(ofSize: max(11, caption.fontSize * s), weight: .bold)
        field.textColor = textColor
        field.backgroundColor = Annotation.captionBackground(for: textColor)
        field.drawsBackground = true
        field.isBordered = false
        field.isBezeled = false
        field.wantsLayer = true
        field.layer?.cornerRadius = 4
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor(white: 0.8, alpha: 1).cgColor
        field.focusRingType = .none
        field.placeholderString = "Type, then Return"
        field.delegate = self
        field.sizeToFit()
        let origin = viewPoint(p)
        let pad = caption.captionPadding * s
        field.frame = CGRect(x: origin.x - pad, y: origin.y - pad * 0.6,
                             width: max(200, field.frame.width + pad * 2), height: field.frame.height + pad * 1.2)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    /// Adds the typed text as markup and removes the text field.
    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let item = Annotation(kind: .text(field.stringValue, at: textPoint), color: textColor, lineWidth: textLineWidth)
        field.delegate = nil
        field.removeFromSuperview()
        if let i = editingIndex, annotations.indices.contains(i) {
            editingIndex = nil
            if case let .text(old, _) = annotations[i].kind, old == field.stringValue {
                // Unchanged: no undo step.
            } else {
                pushUndo()
                if item.isEmpty { annotations.remove(at: i) } else { annotations[i] = item }
            }
        } else if !item.isEmpty {
            editingIndex = nil
            pushUndo()
            annotations.append(item)
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelText() {
        textField?.delegate = nil
        textField?.removeFromSuperview()
        textField = nil
        editingIndex = nil
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commitText(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancelText(); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let t = Tool.allCases.first(where: { $0.key == ch }) {
            tool = t
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While the text field is open, Cmd keys go to the text field.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard textField == nil, window?.firstResponder === self, flags == .command || flags == [.command, .shift],
              let ch = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }
        if ch == "r" { rotate(clockwise: flags == .command); return true }
        if ch == "z" && flags == [.command, .shift] { redo(); return true }
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        switch ch {
        case "z": undo()
        case "c": onCopy?()
        case "s": onSave?()
        case "w": onClose?()
        case "0": resetZoom()
        case "=", "+": zoom(by: 1.5)
        case "-": zoom(by: 1 / 1.5)
        case "k": onCommandPalette?()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: Output

    func flattened() -> NSBitmapImageRep? {
        commitText()
        return Renderer.flatten(image: image, annotations: annotations)
    }
}
