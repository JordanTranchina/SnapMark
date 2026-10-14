import Foundation

/// Images SnapMark captured, opened or saved, newest first (paths in UserDefaults).
enum RecentImages {
    private static let key = "recentImages"
    private static let limit = 50

    static func add(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: key)
    }

    /// Up to `count` existing files: SnapMark's own list first, then the newest
    /// Desktop screenshots.
    static func list(count: Int = 12) -> [URL] {
        let fm = FileManager.default
        var urls = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { fm.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        if urls.count < count {
            let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let files = (try? fm.contentsOfDirectory(at: desktop, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let shots = files
                .filter { $0.lastPathComponent.hasPrefix("Screenshot ") && $0.pathExtension.lowercased() == "png" }
                .sorted { modified($0) > modified($1) }
            let known = Set(urls.map(\.standardizedFileURL.path))
            urls += shots.filter { !known.contains($0.standardizedFileURL.path) }
        }
        return Array(urls.prefix(count))
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
