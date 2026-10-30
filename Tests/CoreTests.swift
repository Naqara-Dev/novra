import Foundation

/// Tests for the parts of Novra that delete things. Run with scripts/test.sh.
/// Uses a scratch folder in ~/Library/Caches, because Novra refuses to touch /tmp by design.
@main
enum CoreTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func check(_ condition: Bool, _ name: String, file: String = #fileID, line: Int = #line) {
        if condition { passes += 1 } else { failures += 1; print("✗ \(name)  (\(file):\(line))") }
    }

    static let root = Cleaner.home.appending(path: "Library/Caches/com.naqara.novra.tests")

    static func write(_ path: String, bytes: Int = 4096) -> URL {
        let url = root.appending(path: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
        return url
    }

    @MainActor
    static func main() async {
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        protectedPaths()
        collapse()
        await trashAndRestore()
        await permanentDelete()
        await readOnlyFolders()
        await inUseIsSkipped()
        ignoreList()
        projectDetection()
        glob()
        shredder()
        sizeParsing()
        versions()

        print(failures == 0 ? "✓ all \(passes) checks passed" : "\(failures) failed, \(passes) passed")
        exit(failures == 0 ? 0 : 1)
    }

    static func protectedPaths() {
        let h = Cleaner.home.path
        for path in ["/", h, h + "/Library", h + "/Documents", h + "/Desktop", h + "/Library/Caches", h + "/.Trash",
                     "/System/Library/Fonts", "/usr/bin", "/Volumes/USB", "/private/tmp/x", "/private/var/db/foo",
                     h + "/Library/Keychains/login.keychain-db", "/private/var/log"] {
            check(Cleaner.isProtected(URL(filePath: path)), "protects \(path)")
        }
        for path in [h + "/Library/Caches/com.example.app", h + "/projects/app/node_modules", "/Applications/Foo.app",
                     "/private/var/log/system.log", "/Library/Caches/com.example.cache"] {
            check(!Cleaner.isProtected(URL(filePath: path)), "allows \(path)")
        }
    }

    static func collapse() {
        let a = URL(filePath: "/x/a"), b = URL(filePath: "/x/a/b"), c = URL(filePath: "/x/c")
        let result = Cleaner.collapse([a: 10, b: 5, c: 1])
        check(Set(result.keys) == [a, c], "nested items are not removed or counted twice")
    }

    @MainActor
    static func trashAndRestore() async {
        let file = write("restore/keep-me.txt")
        let report = await Cleaner.remove([file: 4096], toTrash: true, source: "Novra Tests")
        check(report.removed == 1 && report.movedToTrash, "moves to Trash")
        check(!FileManager.default.fileExists(atPath: file.path), "file left its folder")
        check(report.items.first?.trashed != nil, "remembers where it landed in the Trash")
        guard let record = History.shared.records.first(where: { $0.source == "Novra Tests" }) else {
            check(false, "clean is recorded in History"); return
        }
        let restored = History.shared.restore(record)
        check(restored.restored == 1, "History restores it")
        check(FileManager.default.fileExists(atPath: file.path), "file is back where it was")
        History.shared.forget(record.id)
    }

    @MainActor
    static func permanentDelete() async {
        let folder = root.appending(path: "permanent")
        _ = write("permanent/a.bin")
        _ = write("permanent/sub/b.bin")
        let report = await Cleaner.remove([folder: 8192], toTrash: false, source: "Novra Tests")
        check(report.removed == 1 && !report.movedToTrash, "deletes permanently")
        check(!FileManager.default.fileExists(atPath: folder.path), "folder is gone")
        check(report.items.first?.trashed == nil, "nothing to restore after permanent delete")
        if let record = History.shared.records.first(where: { $0.source == "Novra Tests" }) { History.shared.forget(record.id) }

        let refused = await Cleaner.remove([URL(filePath: Cleaner.home.path + "/Documents"): 1], toTrash: true, source: "Novra Tests")
        check(refused.removed == 0 && refused.failed.count == 1, "refuses to remove a protected folder")
        check(FileManager.default.fileExists(atPath: Cleaner.home.path + "/Documents"), "Documents still there")
    }

    static func ignoreList() {
        let set: Set<String> = ["/Users/x/projects/keep"]
        check(Prefs.isIgnored(URL(filePath: "/Users/x/projects/keep"), in: set), "ignores the folder itself")
        check(Prefs.isIgnored(URL(filePath: "/Users/x/projects/keep/node_modules"), in: set), "ignores what's inside")
        check(!Prefs.isIgnored(URL(filePath: "/Users/x/projects/keeper"), in: set), "doesn't ignore a similar name")
    }

    static func projectDetection() {
        _ = write("code/web/package.json")
        _ = write("code/web/src/index.js")
        _ = write("code/web/node_modules/lib/index.js", bytes: 2_000_000)
        _ = write("code/notes/build/plan.txt", bytes: 2_000_000)   // "build" but not a project
        _ = write("code/site/package.json")
        _ = write("code/site/dist/app.js", bytes: 2_000_000)        // tracked in git, must stay
        _ = write("code/app/package.json")
        _ = write("code/app/.gitignore")
        try? "dist/\n".write(to: root.appending(path: "code/app/.gitignore"), atomically: true, encoding: .utf8)
        _ = write("code/app/dist/bundle.js", bytes: 2_000_000)      // ignored by git: rebuildable
        _ = write("code/thesis/Makefile")
        _ = write("code/thesis/dist/final.pdf", bytes: 2_000_000)   // no repo: leave it alone
        let site = root.appending(path: "code/site")
        for (dir, args) in [(site, ["init", "-q"]), (site, ["add", "dist/app.js", "package.json"]),
                            (root.appending(path: "code/app"), ["init", "-q"])] {
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/git")
            p.arguments = ["-C", dir.path] + args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }
        let found = ProjectScanner.find(in: [root.appending(path: "code")]) { _, _ in }
        let names = Set(found.flatMap { $0.folders.map { $0.url.path.replacingOccurrences(of: root.path + "/", with: "") } })
        check(names.contains("code/web/node_modules"), "finds node_modules in a project")
        check(!names.contains { $0.contains("notes/build") }, "ignores build/ outside projects")
        check(!names.contains { $0.contains("site/dist") }, "skips build output tracked in git")
        check(!names.contains { $0.contains("src") }, "never offers source code")
        check(names.contains("code/app/dist"), "finds dist/ that git ignores")
        check(!names.contains { $0.contains("thesis/dist") }, "leaves dist/ alone outside a git repo")
    }

    static func glob() {
        _ = write("glob/AppOne/GPUCache/x")
        _ = write("glob/AppTwo/GPUCache/y")
        _ = write("glob/AppTwo/Other/z")
        let matches = Glob.expand(root.path + "/glob/*/GPUCache").map(\.lastPathComponent)
        check(matches.count == 2 && matches.allSatisfy { $0 == "GPUCache" }, "wildcards match one level")
        check(Glob.expand("").isEmpty, "empty pattern matches nothing")
    }

    static func shredder() {
        let file = write("shred/secret.txt")
        let report = Shredder.shred([file]) { _, _ in }
        check(report.removed == 1 && !FileManager.default.fileExists(atPath: file.path), "shreds a file")
        let refused = Shredder.shred([URL(filePath: "/System/Library")]) { _, _ in }
        check(refused.removed == 0, "won't shred a protected path")
    }
}

extension CoreTests {
    static func sizeParsing() {
        let docker = "Deleted Images:\nuntagged: foo\n\nTotal reclaimed space: 1.751GB"
        check(abs(Double(Shell.parseSizes(docker, marker: "reclaimed space")) - 1.751e9) < 1e6, "reads Docker's reclaimed space")
        let brew = "==> This operation has freed approximately 120.5MB of disk space."
        check(abs(Double(Shell.parseSizes(brew, marker: "freed approximately")) - 120.5e6) < 1e3, "reads Homebrew's freed space")
        check(Shell.parseSizes("Total reclaimed space: 0B", marker: "reclaimed space") == 0, "zero stays zero")
    }
}

extension CoreTests {
    static func versions() {
        check(Updates.isNewer("1.1", than: "1.0"), "1.1 is newer than 1.0")
        check(Updates.isNewer("1.10", than: "1.9"), "1.10 is newer than 1.9")
        check(!Updates.isNewer("1.1.0", than: "1.1"), "1.1.0 equals 1.1")
        check(!Updates.isNewer("1.0", than: "1.1"), "older is not newer")
        check(Updates.isNewer("2.0", than: "1.99.9"), "major beats minor")
    }
}

extension CoreTests {
    /// Go marks its module cache read-only. Novra should still remove it, without asking Finder.
    static func readOnlyFolders() async {
        for toTrash in [false, true] {
            let file = write("gomod-\(toTrash)/example.com/pkg@v1.0.0/pkg.go")
            let folder = root.appending(path: "gomod-\(toTrash)")
            for dir in [file.deletingLastPathComponent(), file.deletingLastPathComponent().deletingLastPathComponent(), folder] {
                chmod(dir.path, 0o555)
            }
            let report = await Cleaner.remove([folder: 4096], toTrash: toTrash, source: "Novra Tests")
            check(report.removed == 1 && report.failed.isEmpty && !FileManager.default.fileExists(atPath: folder.path),
                  "removes a read-only folder \(toTrash ? "to the Trash" : "permanently")")
            if let landed = report.items.first?.trashed {
                _ = await Shell.run("/bin/chmod", ["-R", "u+w", landed])
                try? FileManager.default.removeItem(atPath: landed)
            }
        }
    }

    /// A folder another program has open is left alone and reported, not forced.
    static func inUseIsSkipped() async {
        let file = write("busy/cache.bin")
        let folder = file.deletingLastPathComponent()
        let holder = Process()
        holder.executableURL = URL(filePath: "/usr/bin/tail")
        holder.arguments = ["-f", file.path]
        holder.standardOutput = FileHandle.nullDevice
        try? holder.run()
        try? await Task.sleep(for: .milliseconds(300))

        let open = await OpenFiles.snapshot()
        check(open.holder(of: folder) == "tail", "sees which program has a folder open")
        check(open.holder(of: root.appending(path: "bus")) == nil, "a name prefix isn't a parent folder")

        let report = await Cleaner.remove([folder: 4096], toTrash: false, source: "Novra Tests")
        check(report.inUse[folder] == "tail" && report.removed == 0 && FileManager.default.fileExists(atPath: file.path),
              "skips a folder that's in use")
        holder.terminate()
        holder.waitUntilExit()

        let after = await Cleaner.remove([folder: 4096], toTrash: false, source: "Novra Tests")
        check(after.removed == 1 && after.inUse.isEmpty, "removes it once nothing holds it")
    }
}
