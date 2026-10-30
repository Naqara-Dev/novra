import Foundation

struct Footprint: Sendable, Hashable {
    var size: Int64
    /// Most recent read or write anywhere inside the item. macOS records when a file is read,
    /// so a tool that is used daily but never changes still counts as used.
    var lastUsed: Date?
}

enum FileSizer {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .contentModificationDateKey, .contentAccessDateKey,
    ]

    /// On-disk size of a file or folder, walking every descendant.
    static func measure(_ url: URL) -> Footprint {
        let values = try? url.resourceValues(forKeys: Set(keys))
        var size = allocated(values)
        var newest = latest(values)
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            return Footprint(size: size, lastUsed: newest)
        }
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return Footprint(size: size, lastUsed: newest) }

        var visited = 0
        for case let child as URL in walker {
            visited += 1
            if visited % 4000 == 0, Task.isCancelled { break }
            guard let v = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            size += allocated(v)
            if let d = latest(v), d > newest ?? .distantPast { newest = d }
        }
        return Footprint(size: size, lastUsed: newest)
    }

    static func size(_ url: URL) -> Int64 { measure(url).size }

    /// Last read or write. A folder's access date changes whenever anything lists it (including Novra),
    /// so folders only count their modification date; files count both.
    private static func latest(_ v: URLResourceValues?) -> Date? {
        if v?.isDirectory == true { return v?.contentModificationDate }
        return [v?.contentModificationDate, v?.contentAccessDate].compactMap { $0 }.max()
    }

    private static func allocated(_ v: URLResourceValues?) -> Int64 {
        Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
    }

    /// Direct children of a folder, including hidden ones. Empty when unreadable.
    static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: []
        )) ?? []
    }

    /// True for cloud placeholders (iCloud Drive, Dropbox, Google Drive...) whose content isn't on this Mac.
    /// Reading one starts a download, so anything that reads file content must skip these.
    static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & 0x4000_0000 != 0 // SF_DATALESS
    }

    static func isDirectory(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return v?.isDirectory == true
    }
}
