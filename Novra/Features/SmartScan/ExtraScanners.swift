import AppKit

/// Cleanups that need more than a path pattern.
enum ExtraScanners {
    /// .DS_Store files Finder sprinkles everywhere. Only folder view settings are lost.
    static func dsStoreFiles(progress: JunkScanner.Progress) -> [JunkItem] {
        let skip: Set<String> = ["Library", ".Trash", "node_modules", ".git", "Caches", "MobileSync", "Developer"]
        let found = Collector<URL>()

        func subfolders(of dir: URL) -> [URL] {
            FileSizer.children(of: dir).filter { child in
                let name = child.lastPathComponent
                if name == ".DS_Store" { found.append(child); return false }
                guard !skip.contains(name), !name.hasPrefix("."),
                      let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]) else { return false }
                return v.isDirectory == true && v.isPackage != true && v.isSymbolicLink != true
            }
        }
        func walk(_ dir: URL, depth: Int) {
            guard depth <= 5, !Task.isCancelled else { return }
            for sub in subfolders(of: dir) { walk(sub, depth: depth + 1) }
        }

        // Two levels in serial, then the rest in parallel.
        let branches = subfolders(of: Cleaner.home).flatMap { subfolders(of: $0) }
        let done = Counter()
        DispatchQueue.concurrentPerform(iterations: branches.count) { index in
            walk(branches[index], depth: 2)
            progress(branches[index].path, Double(done.increment()) / Double(max(branches.count, 1)))
        }
        let files = found.items
        guard !files.isEmpty else { return [] }
        return [JunkItem(name: ".DS_Store files", note: "\(files.count) files · Finder forgets icon positions and view options",
                         urls: files, size: files.map { FileSizer.size($0) }.sum, selectedByDefault: true)]
    }

    /// Copies of Chrome made while it updates. They share disk blocks with Chrome itself,
    /// so the space you get back can be much less than the size shown.
    static func chromiumClones() -> [JunkItem] {
        guard let dir = Glob.userCloneDir else { return [] }
        let clones = FileSizer.children(of: dir).filter { $0.lastPathComponent.hasSuffix(".code_sign_clone") }
        guard !clones.isEmpty else { return [] }
        let running = NSWorkspace.shared.runningApplications.contains { app in
            clones.contains { $0.lastPathComponent.hasPrefix(app.bundleIdentifier ?? "\u{0}") }
        }
        return [JunkItem(name: "Browser update copies",
                         note: running ? "Quit the browser first · shares space with the app, so the real gain may be smaller"
                                       : "Shares space with the app, so the real gain may be smaller",
                         urls: clones, size: clones.map { FileSizer.size($0) }.sum, selectedByDefault: !running)]
    }

    /// Old versions of CLI agents (Claude Code, Cursor Agent, Copilot CLI). The two newest and the one in use stay.
    static func oldToolVersions() -> [JunkItem] {
        let home = Cleaner.home
        let tools: [(String, String)] = [("Claude Code", ".local/share/claude/versions"),
                                         ("Cursor Agent", ".local/share/cursor-agent/versions"),
                                         ("Copilot CLI", ".local/share/copilot/versions")]
        let active = Set(FileSizer.children(of: home.appending(path: ".local/bin")).map { $0.resolvingSymlinksInPath().path })
        return tools.compactMap { name, path in
            let versions = FileSizer.children(of: home.appending(path: path)).sorted {
                (modified($0) ?? .distantPast) > (modified($1) ?? .distantPast)
            }
            let old = versions.dropFirst(2).filter { version in
                !active.contains { $0 == version.path || $0.hasPrefix(version.path + "/") }
            }
            guard !old.isEmpty else { return nil }
            return JunkItem(name: "Old \(name) versions", note: "\(old.count) old · newest two and the one in use are kept",
                            urls: Array(old), size: old.map { FileSizer.size($0) }.sum, selectedByDefault: true)
        }
    }

    /// Extensions VS Code and Cursor marked obsolete after an update but never deleted.
    static func obsoleteEditorExtensions() -> [JunkItem] {
        [("VS Code", ".vscode/extensions"), ("Cursor", ".cursor/extensions")].compactMap { name, path in
            let folder = Cleaner.home.appending(path: path)
            guard let data = try? Data(contentsOf: folder.appending(path: ".obsolete")),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else { return nil }
            let urls = list.filter(\.value).keys.map { folder.appending(path: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return nil }
            return JunkItem(name: "Obsolete \(name) extensions", note: "Replaced by newer versions",
                            urls: urls, size: urls.map { FileSizer.size($0) }.sum, selectedByDefault: true)
        }
    }

    /// Chromium browsers keep the previous version inside the app after updating.
    static func oldBrowserVersions() -> [JunkItem] {
        let apps = [("Google Chrome", "com.google.Chrome", "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions"),
                    ("Microsoft Edge", "com.microsoft.edgemac", "/Applications/Microsoft Edge.app/Contents/Frameworks/Microsoft Edge Framework.framework/Versions"),
                    ("Brave", "com.brave.Browser", "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions")]
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return apps.compactMap { name, bundleID, path in
            // After a background update, the "old" version is the one the open browser runs on:
            // every new tab starts a helper from it. Never offer it while the browser is open.
            guard !running.contains(bundleID) else { return nil }
            let folder = URL(filePath: path)
            let current = folder.appending(path: "Current").resolvingSymlinksInPath().path
            let old = FileSizer.children(of: folder).filter {
                $0.lastPathComponent != "Current" && $0.resolvingSymlinksInPath().path != current
                    && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
            }
            guard !old.isEmpty else { return nil }
            return JunkItem(name: "Old \(name) version", note: "Left behind by the last update.",
                            urls: old, size: old.map { FileSizer.size($0) }.sum, selectedByDefault: false)
        }
    }

    /// Zip files in Downloads that only wrap an installer.
    static func installerArchives(progress: JunkScanner.Progress) -> [JunkItem] {
        let zips = FileSizer.children(of: Cleaner.home.appending(path: "Downloads"))
            .filter { $0.pathExtension.lowercased() == "zip" && !FileSizer.isDataless($0) }
        return zips.compactMap { zip in
            progress(zip.path, 0.8)
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(filePath: "/usr/bin/zipinfo")
            process.arguments = ["-1", zip.path]
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return nil }
            let listing = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let entries = listing.split(separator: "\n")
            let hasInstaller = entries.contains { line in
                [".dmg", ".pkg", ".mpkg"].contains { line.lowercased().hasSuffix($0) }
                    || (line.hasSuffix(".app/") && line.split(separator: "/").count == 1)
            }
            guard hasInstaller else { return nil }
            return JunkItem(name: zip.lastPathComponent, note: "Zip holding an installer or app",
                            urls: [zip], size: FileSizer.size(zip), selectedByDefault: false)
        }
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
