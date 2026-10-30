import Foundation

/// User settings. Read from any thread; the UI binds to the same keys with @AppStorage.
enum Prefs {
    enum Key {
        static let defaultToTrash = "defaultToTrash"
        static let staleDays = "staleDays"
        static let ignoredPaths = "ignoredPaths"
        static let menuBarEnabled = "menuBarEnabled"
        static let lowDiskAlert = "lowDiskAlert"
        static let lowDiskGB = "lowDiskGB"
        static let onboarded = "onboarded"
        static let checkForUpdates = "checkForUpdates"
    }

    private static var defaults: UserDefaults { .standard }

    static var defaultToTrash: Bool { defaults.object(forKey: Key.defaultToTrash) as? Bool ?? true }

    /// How long something can go unused before Novra calls it stale.
    static var staleDays: Int {
        let value = defaults.integer(forKey: Key.staleDays)
        return value > 0 ? value : 90
    }

    static var staleLabel: String {
        switch staleDays {
        case 30: String(localized: "Unused 1+ month")
        case 180: String(localized: "Unused 6+ months")
        case 365: String(localized: "Unused 1+ year")
        default: String(localized: "Unused 3+ months")
        }
    }

    /// On unless turned off; asked during onboarding.
    static var checkForUpdates: Bool { defaults.object(forKey: Key.checkForUpdates) as? Bool ?? true }

    static var lowDiskGB: Int {
        let value = defaults.integer(forKey: Key.lowDiskGB)
        return value > 0 ? value : 10
    }

    // MARK: Ignore list

    static var ignored: Set<String> { Set(defaults.stringArray(forKey: Key.ignoredPaths) ?? []) }

    static func ignore(_ urls: [URL]) {
        var set = ignored
        set.formUnion(urls.map(\.standardizedFileURL.path))
        defaults.set(Array(set).sorted(), forKey: Key.ignoredPaths)
    }

    static func unignore(_ path: String) {
        var set = ignored
        set.remove(path)
        defaults.set(Array(set).sorted(), forKey: Key.ignoredPaths)
    }

    /// True when the path, or a folder containing it, is on the ignore list.
    static func isIgnored(_ url: URL, in set: Set<String> = ignored) -> Bool {
        guard !set.isEmpty else { return false }
        var path = url.standardizedFileURL.path
        while path.count > 1 {
            if set.contains(path) { return true }
            path = (path as NSString).deletingLastPathComponent
        }
        return false
    }
}
