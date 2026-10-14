// Draws the SnapMark app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // Squircle body, inset like Apple's template (824 pt on a 1024 canvas).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.32, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1))!
        .draw(in: shape, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Viewfinder corners.
    NSColor.white.setStroke()
    let corner = NSBezierPath()
    corner.lineWidth = 44
    corner.lineCapStyle = .round
    corner.lineJoinStyle = .round
    let (l, r, b, t, len): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (250, 774, 250, 774, 140)
    for (x, y, dx, dy) in [(l, t, 1, -1), (r, t, -1, -1), (l, b, 1, 1), (r, b, -1, 1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        corner.move(to: NSPoint(x: x + dx * len, y: y))
        corner.line(to: NSPoint(x: x, y: y))
        corner.line(to: NSPoint(x: x, y: y + dy * len))
    }
    corner.stroke()

    // Red markup arrow across the frame.
    let red = NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 1)
    red.setStroke(); red.setFill()
    let shaft = NSBezierPath()
    shaft.lineWidth = 52
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: 360, y: 360))
    shaft.line(to: NSPoint(x: 590, y: 590))
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 680, y: 680))
    head.line(to: NSPoint(x: 500, y: 640))
    head.line(to: NSPoint(x: 640, y: 500))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 24
    head.fill(); head.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let set = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try draw(size).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size * 2).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try draw(1024).write(to: root.appendingPathComponent("build/AppIcon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
