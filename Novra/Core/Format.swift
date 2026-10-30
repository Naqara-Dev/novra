import Foundation

extension Int64 {
    /// Human-readable size, e.g. "18.7 GB".
    var byteString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

// Formatters are costly to create and safe to share for formatting, so make each once.
nonisolated(unsafe) private let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
}()

private let ageFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 1
    formatter.allowedUnits = [.year, .month, .weekOfMonth, .day]
    return formatter
}()

extension Date {
    /// "3 months ago", "yesterday", ...
    var relativeString: String { relativeFormatter.localizedString(for: self, relativeTo: .now) }

    /// "3 months", "2 weeks": how long ago, without the "ago".
    var ageString: String { ageFormatter.string(from: self, to: .now) ?? relativeString }

    var isStale: Bool { self < Date.now.addingTimeInterval(-Double(Prefs.staleDays) * 24 * 3600) }
}

extension URL {
    /// Path with the home folder shortened to "~".
    var tildePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

extension Sequence where Element == Int64 {
    var sum: Int64 { reduce(0, +) }
}
