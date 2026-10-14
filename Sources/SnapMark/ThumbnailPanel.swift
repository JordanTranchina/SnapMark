import AppKit

/// Floating preview in the bottom-left corner after a capture, like the macOS
/// screenshot thumbnail. Click opens the editor; it fades out after 3 seconds
/// (paused while the mouse is over it). It never takes focus.
final class ThumbnailPanel: NSPanel {
    var onClick: (() -> Void)?
    var onDismissed: (() -> Void)?
    private var timer: Timer?
    private var dismissing = false

    private static let width: CGFloat = 200
    private static let inset: CGFloat = 20
    private static let lifetime: TimeInterval = 3

    init(image: NSImage) {
        let w = ThumbnailPanel.width
        let h = max(40, min(w * 1.5, w * image.size.height / max(image.size.width, 1)))
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = ThumbnailView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        view.image = image
        view.onClick = { [weak self] in
            self?.onClick?()
            self?.dismiss(animated: false)
        }
        view.onHover = { [weak self] inside in
            if inside { self?.timer?.invalidate() } else { self?.startTimer() }
        }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let final = NSRect(x: vf.minX + Self.inset, y: vf.minY + Self.inset,
                           width: frame.width, height: frame.height)
        setFrame(final.offsetBy(dx: -40, dy: 0), display: false)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().setFrame(final, display: true)
            animator().alphaValue = 1
        }
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.lifetime, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss(animated: Bool = true) {
        guard !dismissing else { return }
        dismissing = true
        timer?.invalidate()
        let finish = { [weak self] in
            self?.orderOut(nil)
            self?.onDismissed?()
        }
        guard animated else { finish(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: finish)
    }
}

private final class ThumbnailView: NSView {
    var image: NSImage?
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseUp(with event: NSEvent) { onClick?() }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
