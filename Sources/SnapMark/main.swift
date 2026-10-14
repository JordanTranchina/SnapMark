import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
// SnapMark is always light (white windows), even in Dark Mode.
app.appearance = NSAppearance(named: .aqua)
app.run()
