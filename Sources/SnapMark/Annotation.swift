import AppKit

enum Tool: Int, CaseIterable {
    case crop, arrow, rectangle, blackout, pen, text, step

    var key: String {
        switch self {
        case .crop: return "c"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .blackout: return "b"
        case .pen: return "p"
        case .text: return "t"
        case .step: return "s"
        }
    }

    var symbol: String {
        switch self {
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .blackout: return "rectangle.fill"
        case .pen: return "scribble"
        case .text: return "textformat"
        case .step: return "1.circle"
        }
    }

    var label: String {
        switch self {
        case .crop: return "Crop (C)"
        case .arrow: return "Arrow (A)"
        case .rectangle: return "Rectangle (R)"
        case .blackout: return "Blackout (B)"
        case .pen: return "Pen (P)"
        case .text: return "Text (T)"
        case .step: return "Step (S)"
        }
    }
}

let palette: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .black, .white]

enum AnnotationKind {
    case arrow(from: CGPoint, to: CGPoint)
    /// Solid black box that hides what is under it.
    case blackout(CGRect)
    /// Numbered circle; its number comes from its order among steps.
    case step(CGPoint)
    case rectangle(CGRect)
    case pen([CGPoint])
    case text(String, at: CGPoint)
}

/// One markup item. All geometry is in image points, top-left origin.
struct Annotation {
    var kind: AnnotationKind
    var color: NSColor
    var lineWidth: CGFloat

    var fontSize: CGFloat { lineWidth * 5 }

    /// Bounds of a text item in image points (nil for other kinds).
    var textBounds: CGRect? {
        guard case let .text(string, point) = kind else { return nil }
        let size = (string as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold)])
        return CGRect(origin: point, size: size)
    }

    static func captionBackground(for textColor: NSColor) -> NSColor {
        let white = textColor.usingColorSpace(.deviceRGB).map { $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.blueComponent > 0.9 } ?? false
        return white ? .black : .white
    }

    /// Padding of the caption box around text.
    var captionPadding: CGFloat { fontSize * 0.25 }

    /// The caption box (text plus padding), used for drawing and hit-testing.
    var captionBounds: CGRect? {
        textBounds?.insetBy(dx: -captionPadding, dy: -captionPadding * 0.6)
    }

    func offset(by d: CGPoint) -> Annotation {
        mapped { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
    }

    /// Moves every point through `m` (used for crop and rotate). Text stays upright,
    /// with its center moved.
    func mapped(_ m: (CGPoint) -> CGPoint) -> Annotation {
        var copy = self
        switch kind {
        case let .arrow(a, b): copy.kind = .arrow(from: m(a), to: m(b))
        case let .rectangle(r):
            let a = m(CGPoint(x: r.minX, y: r.minY)), b = m(CGPoint(x: r.maxX, y: r.maxY))
            copy.kind = .rectangle(CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                          width: abs(b.x - a.x), height: abs(b.y - a.y)))
        case let .blackout(r):
            let a = m(CGPoint(x: r.minX, y: r.minY)), b = m(CGPoint(x: r.maxX, y: r.maxY))
            copy.kind = .blackout(CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                         width: abs(b.x - a.x), height: abs(b.y - a.y)))
        case let .pen(points): copy.kind = .pen(points.map(m))
        case let .step(c): copy.kind = .step(m(c))
        case let .text(s, _):
            let r = textBounds ?? .zero
            let c = m(CGPoint(x: r.midX, y: r.midY))
            copy.kind = .text(s, at: CGPoint(x: c.x - r.width / 2, y: c.y - r.height / 2))
        }
        return copy
    }

    /// True when the item is too small to keep (for example, a click with no drag).
    var isEmpty: Bool {
        switch kind {
        case let .arrow(a, b): return hypot(b.x - a.x, b.y - a.y) < 4
        case let .rectangle(r), let .blackout(r): return r.width < 3 || r.height < 3
        case let .pen(points): return points.count < 2
        case .step: return false
        case let .text(s, _): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static let stepRadius: CGFloat = 13

    /// Draws into the current (flipped) graphics context. `step` is this item's
    /// number if it is a step.
    func draw(step: Int = 0) {
        switch kind {
        case let .step(c):
            let r = Annotation.stepRadius
            let circle = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            color.setFill()
            circle.fill()
            NSColor.white.setStroke()
            circle.lineWidth = 2
            circle.stroke()
            let rgb = color.usingColorSpace(.deviceRGB)
            let light = (rgb?.greenComponent ?? 0) > 0.7 && (rgb?.redComponent ?? 0) > 0.7  // yellow or white
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: step >= 10 ? 12 : 14, weight: .bold),
                .foregroundColor: light ? NSColor.black : NSColor.white,
            ]
            let label = "\(step)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2), withAttributes: attrs)

        case let .rectangle(r):
            color.setStroke()
            let path = NSBezierPath(roundedRect: r, xRadius: lineWidth, yRadius: lineWidth)
            path.lineWidth = lineWidth
            path.stroke()

        case let .blackout(r):
            // Opaque black on whole points with no anti-aliasing, so every covered
            // pixel is replaced with pure black in the saved image.
            let ctx = NSGraphicsContext.current?.cgContext
            ctx?.saveGState()
            ctx?.setShouldAntialias(false)
            ctx?.setBlendMode(.copy)
            ctx?.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx?.fill(r.integral)
            ctx?.restoreGState()

        case let .pen(points):
            guard let first = points.first else { return }
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: first)
            for p in points.dropFirst() { path.line(to: p) }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

        case let .arrow(from, to):
            let angle = atan2(to.y - from.y, to.x - from.x)
            let head = max(lineWidth * 4, 14)
            let spread = CGFloat.pi / 7
            let left = CGPoint(x: to.x - head * cos(angle - spread), y: to.y - head * sin(angle - spread))
            let right = CGPoint(x: to.x - head * cos(angle + spread), y: to.y - head * sin(angle + spread))
            // Stop the shaft inside the head so the tip stays sharp.
            let shaftEnd = CGPoint(x: to.x - head * 0.7 * cos(angle), y: to.y - head * 0.7 * sin(angle))

            color.setStroke()
            color.setFill()
            let shaft = NSBezierPath()
            shaft.move(to: from)
            shaft.line(to: shaftEnd)
            shaft.lineWidth = lineWidth
            shaft.lineCapStyle = .round
            shaft.stroke()

            let tip = NSBezierPath()
            tip.move(to: to)
            tip.line(to: left)
            tip.line(to: right)
            tip.close()
            tip.fill()

        case let .text(string, point):
            // Caption: a rounded box behind the text. White text gets a black box.
            if let box = captionBounds {
                let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
                Annotation.captionBackground(for: color).setFill()
                path.fill()
                NSColor(white: 0.8, alpha: 1).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: color,
            ]
            (string as NSString).draw(at: point, withAttributes: attrs)
        }
    }
}

enum Renderer {
    /// Draws the image and its markup in image points, into a flipped context.
    static func draw(image: NSImage, annotations: [Annotation]) {
        image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero,
                   operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        var steps = 0
        for a in annotations {
            if case .step = a.kind { steps += 1 }
            a.draw(step: steps)
        }
    }

    /// Makes a full-resolution bitmap of the image with its markup.
    static func flatten(image: NSImage, annotations: [Annotation]) -> NSBitmapImageRep? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pw = cg.width, ph = cg.height
        let space = cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Map image points (top-left origin) to pixels (bottom-left origin).
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: CGFloat(pw) / image.size.width, y: -CGFloat(ph) / image.size.height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw(image: image, annotations: annotations)
        NSGraphicsContext.restoreGraphicsState()

        guard let out = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: out)
        rep.size = image.size // keeps Retina DPI in the saved PNG
        return rep
    }

    static func crop(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sx = CGFloat(cg.width) / image.size.width
        let sy = CGFloat(cg.height) / image.size.height
        let pixelRect = CGRect(x: rect.minX * sx, y: rect.minY * sy,
                               width: rect.width * sx, height: rect.height * sy).integral
        guard let cropped = cg.cropping(to: pixelRect) else { return nil }
        return NSImage(cgImage: cropped,
                       size: CGSize(width: CGFloat(cropped.width) / sx,
                                    height: CGFloat(cropped.height) / sy))
    }

    /// Rotates by 90°, clockwise or counter-clockwise, keeping the pixel density.
    static func rotate(_ image: NSImage, clockwise: Bool) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: cg.height, height: cg.width, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // CGContext is y-up: a clockwise turn on screen is -90° here.
        ctx.translateBy(x: CGFloat(cg.height) / 2, y: CGFloat(cg.width) / 2)
        ctx.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2, y: -CGFloat(cg.height) / 2,
                                width: CGFloat(cg.width), height: CGFloat(cg.height)))
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: CGSize(width: image.size.height, height: image.size.width))
    }
}
