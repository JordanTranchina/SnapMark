import AppKit

enum CaptureMode {
    case fullScreen   // Cmd+Shift+3
    case selection    // Cmd+Shift+4
    case toolbar      // Cmd+Shift+5
}

/// Takes screenshots with the built-in /usr/sbin/screencapture tool, so the
/// selection UI (crosshair, Space for window capture, Esc to cancel) is the
/// same as the default macOS UI.
enum Capture {
    /// Writes the screenshot straight to the Desktop and returns its URL (nil if cancelled).
    static func run(_ mode: CaptureMode, completion: @escaping (URL?) -> Void) {
        let url = SaveLocation.newFileURL()

        var args: [String] = []
        switch mode {
        case .fullScreen: args = ["-m"]          // main display
        case .selection:  args = ["-i"]          // interactive area or window
        case .toolbar:    args = ["-i", "-U"]    // interactive with the screenshot toolbar
        }
        args.append(url.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                // No file means the user pressed Esc.
                completion(FileManager.default.fileExists(atPath: url.path) ? url : nil)
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("SnapMark: screencapture failed: \(error)")
            completion(nil)
        }
    }
}
