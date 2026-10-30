import AppKit

struct CleanReport: Sendable {
    var freed: Int64 = 0
    var removed = 0
    var failed: [URL] = []
    var movedToTrash = false
    /// Items left alone because a running program had files open inside them, with that program's name.
    var inUse: [URL: String] = [:]
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
    /// the Trash). Anything that belongs to an open app, or that a running program has open, is skipped
    /// and reported, never forced.
    /// Only items owned by someone else (root-owned apps, system logs) go through a password prompt.
    static func remove(_ items: [URL: Int64], toTrash: Bool, source: String = "Novra") async -> CleanReport {
        let targets = collapse(items)
        await Activity.shared.begin(toTrash ? "Moving to Trash…" : "Deleting permanently…", total: targets.count)
        let open = await OpenFiles.snapshot()
        let apps = RunningApps.current()
        var (report, needsAuth) = await Task.detached(priority: .userInitiated) {
            removeDirectly(targets, toTrash: toTrash, open: open, apps: apps) { name, bytes in
                Task { @MainActor in Activity.shared.step(name, bytes: bytes) }
            }
        }.value
        if !needsAuth.isEmpty {
            // Apps in /Applications installed by an admin can go to the Trash through Finder, which asks
            // for the password itself. Everything else that needs a password is deleted as admin.
            let viaFinder = toTrash ? needsAuth.keys.filter { $0.path.hasPrefix("/Applications/") } : []
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

    private static func removeDirectly(_ targets: [URL: Int64], toTrash: Bool, open: OpenFiles, apps: RunningApps,
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
            // Last check before anything moves: an app that's open (or has files open here) wins.
            if let holder = open.holder(of: url) ?? apps.owner(of: url) {
                report.inUse[url] = holder
                continue
            }
            let toTrashHere = toTrash && !url.path.hasPrefix(trashPath)
            var landed: NSURL?
            var result = attempt(url, toTrash: toTrashHere, landed: &landed)
            // Tools like Go mark their caches read-only. They're still yours, so make them writable and try again.
            if result == .denied && isOwnedByMe(url) {
                makeWritable(url, recursive: !toTrashHere)
                result = attempt(url, toTrash: toTrashHere, landed: &landed)
                if result == .denied && toTrashHere {
                    makeWritable(url, recursive: true)
                    result = attempt(url, toTrash: toTrashHere, landed: &landed)
                }
            }
            switch result {
            case .done:
                report.freed += size
                report.removed += 1
                report.items.append(CleanRecord.Item(original: url.path, trashed: landed?.path, size: size))
            case .denied where !isOwnedByMe(url):
                needsAuth[url] = size
            case .denied, .failed:
                report.failed.append(url)
            }
        }
        return (report, needsAuth)
    }

    private enum Attempt { case done, denied, failed }

    private static func attempt(_ url: URL, toTrash: Bool, landed: inout NSURL?) -> Attempt {
        do {
            if toTrash {
                try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            } else {
                try FileManager.default.removeItem(at: url)
            }
            return .done
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            return .denied
        } catch {
            let nsError = error as NSError
            let codes = [nsError] + nsError.underlyingErrors.map { $0 as NSError }
            return codes.contains { $0.code == Int(EACCES) || $0.code == Int(EPERM) } ? .denied : .failed
        }
    }

    private static func isOwnedByMe(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_uid == getuid()
    }

    /// Adds owner write permission to a folder (and, if asked, to every folder inside it).
    private static func makeWritable(_ url: URL, recursive: Bool) {
        func addWrite(_ path: String) {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR else { return }
            if info.st_mode & S_IWUSR == 0 { chmod(path, (info.st_mode & 0o7777) | S_IWUSR) }
        }
        addWrite(url.deletingLastPathComponent().path)
        addWrite(url.path)
        guard recursive, let walker = FileManager.default.enumerator(atPath: url.path) else { return }
        while let relative = walker.nextObject() as? String {
            addWrite(url.path + "/" + relative)
        }
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    private static func finderDelete(_ urls: [URL]) async -> Bool {
        let list = urls.map { "POSIX file \"\(escape($0.path))\"" }.joined(separator: ", ")
        return await runAppleScript("tell application \"Finder\" to delete {\(list)}")
    }

    /// Permanently empties the user's Trash. Read-only folders (left there by tools like Go) are made
    /// writable first, so nothing has to go through Finder and its "in use" dialogs.
    static func emptyTrash() async -> Bool {
        guard SystemInfo.hasFullDiskAccess else {
            // Without Full Disk Access Novra can't see inside the Trash; only Finder can empty it.
            return await runAppleScript("tell application \"Finder\" to empty trash")
        }
        return await Task.detached {
            let fm = FileManager.default
            for url in FileSizer.children(of: trashFolder) {
                if (try? fm.removeItem(at: url)) == nil, isOwnedByMe(url) {
                    makeWritable(url, recursive: true)
                    try? fm.removeItem(at: url)
                }
            }
            return FileSizer.children(of: trashFolder).allSatisfy { $0.lastPathComponent == ".DS_Store" }
        }.value
    }

    /// Runs in its own process, so a Finder dialog never freezes Novra's window.
    private static func runAppleScript(_ source: String) async -> Bool {
        await Shell.run("/usr/bin/osascript", ["-e", source]).status == 0
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
