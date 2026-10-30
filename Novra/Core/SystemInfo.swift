import AppKit

enum SystemInfo {
    static let repository = "https://github.com/Naqara-Dev/novra"
    static let releases = repository + "/releases"
    static let issues = repository + "/issues/new"

    struct Disk: Sendable {
        var total: Int64
        var free: Int64
        var used: Int64 { max(total - free, 0) }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    static func disk() -> Disk {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let v = try? URL(filePath: "/").resourceValues(forKeys: keys)
        return Disk(total: Int64(v?.volumeTotalCapacity ?? 0),
                    free: v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Full Disk Access lets Novra see Safari, Mail and Trash data.
    static var hasFullDiskAccess: Bool {
        let probe = Cleaner.home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db").path
        let fd = Darwin.open(probe, O_RDONLY)
        if fd >= 0 { close(fd); return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: Cleaner.home.appending(path: "Library/Safari").path)) != nil
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    @MainActor
    static func openLoginItemsSettings() {
        open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    @MainActor
    static func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    @MainActor
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// "Google Chrome" for "com.google.Chrome", when that app is installed.
    static func appName(forBundleID id: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
