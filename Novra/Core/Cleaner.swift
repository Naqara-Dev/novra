import AppKit

struct CleanReport: Sendable {
    var freed: Int64 = 0
    var removed = 0
    var failed: [URL] = []
    var movedToTrash = false
    /// What was removed and, for the Trash, where it landed. Used by History to restore.
    var items: [CleanRecord.Item] = []
}

/// The only place in Novra that deletes anything.
enum Cleaner {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var trashFolder: URL { home.appending(path: ".Trash") }

    /// Folders Novra must never remove as a whole, plus anything outside
    /// the home folder, /Applications and /Library.
    static func isProtected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let h = home.path
        let roots = ["/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin",
                     "/private", "/var", "/etc", "/opt", "/Volumes"]
        let homeFolders = ["", "/Library", "/Documents", "/Desktop", "/Downloads", "/Pictures", "/Movies",
                           "/Music", "/.Trash", "/Applications", "/Library/Caches", "/Library/Application Support",
                           "/Library/Preferences", "/Library/Containers", "/Library/Group Containers",
                           "/Library/Logs", "/Library/Developer", "/Library/Mobile Documents",
                           "/Library/CloudStorage", "/Library/Keychains"].map { h + $0 }
        if roots.contains(p) || homeFolders.contains(p) || p.hasPrefix("/System/") { return true }
        if p.hasPrefix(h + "/Library/Keychains/") { return true }
        if p.hasPrefix(h + "/") || p.hasPrefix("/Applications/") || p.hasPrefix("/Library/") { return false }
        // Foundation shortens /private/var/... to /var/... when standardizing, so accept both spellings.
        let allowed = (systemJunkRoots + userTempRoots).flatMap { [$0, $0.replacingOccurrences(of: "/private/var/", with: "/var/")] }
        return !allowed.contains { p.hasPrefix($0) && p.count > $0.count }
    }

    /// System locations that only hold logs and caches. Removing inside them needs the admin password.
    static let systemJunkRoots = [
        "/private/var/log/", "/private/var/db/diagnostics/", "/private/var/db/DiagnosticPipeline/",
        "/private/var/db/powerlog/", "/private/var/db/reportmemoryexception/",
    ]

    /// This user's own cache and temp folders under /var/folders.
    static var userTempRoots: [String] {
        [Glob.userCacheDir, Glob.userTempDir, Glob.userCloneDir].compactMap { $0?.path }.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
    }

    /// Drops any item whose parent folder is also in the list, so nothing is counted twice.
    static func collapse(_ items: [URL: Int64]) -> [URL: Int64] {
        let paths = Set(items.keys.map { $0.standardizedFileURL.path })
        return items.filter { url, _ in
            var parent = url.standardizedFileURL.deletingLastPathComponent()
            while parent.path != "/" {
                if paths.contains(parent.path) { return false }
                parent = parent.deletingLastPathComponent()
            }
            return true
        }
    }

    /// Moves items to the Trash (or deletes them when `toTrash` is false, or when they already live in
    /// the Trash). Items that need an admin password are handed to Finder, which asks for it.
    static func remove(_ items: [URL: Int64], toTrash: Bool, source: String = "Novra") async -> CleanReport {
        let targets = collapse(items)
        await Activity.shared.begin(toTrash ? "Moving to Trash…" : "Deleting permanently…", total: targets.count)
        var (report, needsAuth) = await Task.detached(priority: .userInitiated) {
            removeDirectly(targets, toTrash: toTrash) { name, bytes in
                Task { @MainActor in Activity.shared.step(name, bytes: bytes) }
            }
        }.value
        if !needsAuth.isEmpty {
            // Your own files go through Finder (to the Trash); system logs and caches are deleted as admin.
            let home = Cleaner.home.path + "/"
            let recoverable = [home, "/Applications/", "/Library/LaunchAgents/", "/Library/LaunchDaemons/", "/Library/PrivilegedHelperTools/"]
            // Finder only moves to the Trash, so it's used only when that's what was asked for.
            let viaFinder = toTrash ? needsAuth.keys.filter { url in recoverable.contains { url.path.hasPrefix($0) } } : []
            let viaAdmin = needsAuth.keys.filter { !viaFinder.contains($0) }
            if !viaFinder.isEmpty { _ = await finderDelete(viaFinder) }
            if !viaAdmin.isEmpty {
                let list = viaAdmin.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
                _ = await Shell.runAsAdmin("/bin/rm -rf \(list)")
            }
            // Judge each item by whether it's actually gone.
            for (url, size) in needsAuth {
                if !FileManager.default.fileExists(atPath: url.path) {
                    report.freed += size
                    report.removed += 1
                    report.items.append(CleanRecord.Item(original: url.path, trashed: nil, size: size))
                } else {
                    report.failed.append(url)
                }
            }
        }
        await Activity.shared.finish(report)
        await History.shared.add(source: source, report: report)
        return report
    }

    private static func removeDirectly(_ targets: [URL: Int64], toTrash: Bool,
                                       step: @Sendable (String, Int64) -> Void) -> (CleanReport, [URL: Int64]) {
        var report = CleanReport(movedToTrash: toTrash)
        var needsAuth: [URL: Int64] = [:]
        let fm = FileManager.default
        let trashPath = trashFolder.path + "/"
        for (url, size) in targets.sorted(by: { $0.key.path < $1.key.path }) {
            let freedBefore = report.freed
            defer { step(url.tildePath, report.freed - freedBefore) }
            guard !isProtected(url) else { report.failed.append(url); continue }
            guard fm.fileExists(atPath: url.path) || isSymlink(url) else { continue }
            do {
                var landed: NSURL?
                if toTrash && !url.path.hasPrefix(trashPath) {
                    try fm.trashItem(at: url, resultingItemURL: &landed)
                } else {
                    try fm.removeItem(at: url)
                }
                report.freed += size
                report.removed += 1
                report.items.append(CleanRecord.Item(original: url.path, trashed: landed?.path, size: size))
            } catch let error as CocoaError where error.code == .fileWriteNoPermission {
                needsAuth[url] = size
            } catch {
                if (error as NSError).underlyingErrors.contains(where: { ($0 as NSError).code == Int(EACCES) || ($0 as NSError).code == Int(EPERM) }) {
                    needsAuth[url] = size
                } else {
                    report.failed.append(url)
                }
            }
        }
        return (report, needsAuth)
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    @MainActor
    private static func finderDelete(_ urls: [URL]) async -> Bool {
        let list = urls.map { "POSIX file \"\(escape($0.path))\"" }.joined(separator: ", ")
        return runAppleScript("tell application \"Finder\" to delete {\(list)}")
    }

    /// Permanently empties the user's Trash.
    static func emptyTrash() async -> Bool {
        let leftovers = await Task.detached {
            let fm = FileManager.default
            for url in FileSizer.children(of: trashFolder) { try? fm.removeItem(at: url) }
            return FileSizer.children(of: trashFolder).filter { $0.lastPathComponent != ".DS_Store" }.count
        }.value
        if leftovers == 0 && SystemInfo.hasFullDiskAccess { return true }
        return await MainActor.run { runAppleScript("tell application \"Finder\" to empty trash") }
    }

    @MainActor
    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
