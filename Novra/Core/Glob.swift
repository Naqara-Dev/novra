import Foundation

enum Glob {
    /// Expands "~" and "*"/"?" wildcards in any path component, e.g. "~/Library/Application Support/*/GPUCache".
    static func expand(_ pattern: String) -> [URL] {
        guard !pattern.isEmpty else { return [] }
        let full = pattern.hasPrefix("~") ? Cleaner.home.path + pattern.dropFirst() : pattern
        var current = [URL(filePath: "/")]
        for component in full.split(separator: "/").map(String.init) {
            if component.contains("*") || component.contains("?") {
                current = current.flatMap { dir in
                    FileSizer.children(of: dir).filter { matches($0.lastPathComponent, component) }
                }
            } else {
                current = current.map { $0.appending(path: component) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
            }
            if current.isEmpty { break }
        }
        return current
    }

    static func matches(_ name: String, _ pattern: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }

    /// The per-user folders macOS keeps under /var/folders.
    static var userCacheDir: URL? { darwinDir(_CS_DARWIN_USER_CACHE_DIR) }
    static var userTempDir: URL? { darwinDir(_CS_DARWIN_USER_TEMP_DIR) }
    /// Sibling of the temp folder where code-signing clones live.
    static var userCloneDir: URL? { userTempDir?.deletingLastPathComponent().appending(path: "X") }

    private static func darwinDir(_ name: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard confstr(name, &buffer, buffer.count) > 0 else { return nil }
        return URL(filePath: String(cString: buffer)).resolvingSymlinksInPath()
    }
}
