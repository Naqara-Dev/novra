import Foundation

struct ProjectFolder: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let footprint: Footprint
}

/// A code project and the rebuildable folders inside it.
struct ProjectJunk: Identifiable, Sendable {
    var id: String { project.path }
    let project: URL
    let folders: [ProjectFolder]
    var size: Int64 { folders.map(\.footprint.size).sum }
    var lastUsed: Date? { folders.compactMap(\.footprint.lastUsed).max() }
}

/// Finds rebuildable folders (node_modules, build, dist, ...) inside code projects.
enum ProjectScanner {
    /// Folder names that are build output or downloaded dependencies when they sit next to a project file.
    static let artifactNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".output", ".svelte-kit", ".astro", ".angular", ".turbo", ".parcel-cache",
        "dist", "build", "target", ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        ".tox", ".nox", ".gradle", ".dart_tool", ".cxx", ".expo", "Pods", "coverage", ".zig-cache", "zig-out", ".build",
    ]

    /// Names that are also common for real folders (a thesis "dist", a "build" of photos), so they only count
    /// when git says they're ignored. Outside a git repo they are left alone.
    private static let ambiguous: Set<String> = ["build", "dist", "target", "coverage", "venv", ".build"]

    static let markers: Set<String> = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "requirements.txt", "setup.py", "pom.xml",
        "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "Gemfile", "composer.json",
        "pubspec.yaml", "Package.swift", "Makefile", "build.zig", "Podfile",
    ]

    private static let skippedRoots: Set<String> = ["Library", "Applications", "Pictures", "Music", "Movies", "Public"]

    /// How to get a folder back after removing it.
    static func hint(for name: String) -> String {
        switch name {
        case "node_modules": String(localized: "Dependencies. Run npm, yarn or pnpm install to get them back.")
        case ".next", ".nuxt", ".output", ".svelte-kit", ".astro", ".angular", ".turbo", ".parcel-cache":
            String(localized: "Framework build cache. Rebuilt on the next dev or build run.")
        case ".venv", "venv": String(localized: "Python environment. Recreate it and pip install again.")
        case "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", ".nox": String(localized: "Python tool cache. Rebuilt automatically.")
        case "Pods": String(localized: "CocoaPods dependencies. Run pod install to get them back.")
        case ".gradle", ".cxx": String(localized: "Gradle project cache. Rebuilt on the next build.")
        case "target": String(localized: "Rust or Java build output. Rebuilt on the next build.")
        case ".dart_tool": String(localized: "Dart/Flutter tool cache. Run flutter pub get.")
        case "coverage": String(localized: "Test coverage report.")
        default: String(localized: "Build output. Rebuilt on the next build.")
        }
    }

    /// Smart Scan rows: one per project, ticked when untouched for a month.
    static func scan(progress: JunkScanner.Progress) -> [JunkItem] {
        let month = Date.now.addingTimeInterval(-30 * 86_400)
        return find(progress: progress).map { project in
            let names = project.folders.sorted { $0.footprint.size > $1.footprint.size }.map(\.url.lastPathComponent)
            let when = project.lastUsed.map { "used \($0.relativeString)" } ?? "never used"
            return JunkItem(name: project.project.lastPathComponent,
                            note: "\(names.joined(separator: ", ")) · \(when) · \(project.project.deletingLastPathComponent().tildePath)",
                            urls: project.folders.map(\.url), size: project.size,
                            selectedByDefault: (project.lastUsed ?? .distantPast) < month)
        }
    }

    static func find(in searchRoots: [URL]? = nil, progress: JunkScanner.Progress) -> [ProjectJunk] {
        let home = Cleaner.home
        let roots = searchRoots ?? FileSizer.children(of: home).filter {
            !$0.lastPathComponent.hasPrefix(".") && !skippedRoots.contains($0.lastPathComponent) && FileSizer.isDirectory($0)
        }

        // Look at each top-level folder's children in parallel; most of the time goes into walking big trees.
        let found = Collector<URL>()
        var branches = roots
        var depth = 0
        // Split two levels deep so a single big folder like ~/projects doesn't end up on one thread.
        while depth < 2 {
            var next: [URL] = []
            for dir in branches {
                let (artifacts, subfolders) = inspect(dir)
                artifacts.forEach(found.append)
                next += subfolders
            }
            branches = next
            depth += 1
        }
        let walked = Counter()
        let startDepth = depth
        DispatchQueue.concurrentPerform(iterations: branches.count) { index in
            guard !Task.isCancelled else { return }
            walk(branches[index], depth: startDepth, into: found)
            let done = walked.increment()
            progress(branches[index].path, 0.4 * Double(done) / Double(max(branches.count, 1)))
        }
        guard !Task.isCancelled else { return [] }

        let ignored = Prefs.ignored
        let candidates = found.items.filter { !Prefs.isIgnored($0, in: ignored) }
        let keep = Collector<Int>()
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            let url = candidates[index]
            if !ambiguous.contains(url.lastPathComponent) || isIgnoredByGit(url) { keep.append(index) }
        }
        let folders = keep.items.sorted().map { candidates[$0] }

        // node_modules folders hold hundreds of thousands of files, so measure them in parallel too.
        let measured = Collector<ProjectFolder>()
        let counter = Counter()
        DispatchQueue.concurrentPerform(iterations: folders.count) { index in
            guard !Task.isCancelled else { return }
            let footprint = FileSizer.measure(folders[index])
            if footprint.size > 1_000_000 { measured.append(ProjectFolder(url: folders[index], footprint: footprint)) }
            let done = counter.increment()
            if done % 4 == 0 { progress(folders[index].path, 0.4 + 0.6 * Double(done) / Double(max(folders.count, 1))) }
        }

        return Dictionary(grouping: measured.items) { $0.url.deletingLastPathComponent() }
            .map { ProjectJunk(project: $0.key, folders: $0.value.sorted { $0.footprint.size > $1.footprint.size }) }
            .sorted { $0.size > $1.size }
    }

    /// Build folders directly inside `dir` (when it is a project), and the subfolders worth walking into.
    private static func inspect(_ dir: URL) -> (artifacts: [URL], subfolders: [URL]) {
        let children = FileSizer.children(of: dir)
        let names = Set(children.map(\.lastPathComponent))
        let isProject = !names.isDisjoint(with: markers) || names.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".csproj") }
        var artifacts: [URL] = []
        var subfolders: [URL] = []
        for child in children {
            let name = child.lastPathComponent
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                  values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true else { continue }
            if isProject && artifactNames.contains(name) {
                if !FileManager.default.fileExists(atPath: child.appending(path: ".git").path), !hasTrackedFiles(child) {
                    artifacts.append(child)
                }
                continue
            }
            if name.hasPrefix(".") || name == "node_modules" { continue }
            subfolders.append(child)
        }
        return (artifacts, subfolders)
    }

    private static func walk(_ dir: URL, depth: Int, into found: Collector<URL>) {
        guard depth <= 6, !Task.isCancelled else { return }
        let (artifacts, subfolders) = inspect(dir)
        artifacts.forEach(found.append)
        for sub in subfolders { walk(sub, depth: depth + 1, into: found) }
    }

    /// A real git binary. /usr/bin/git is a stub that pops up an install prompt when the tools are missing.
    private static let git: String? = ["/Library/Developer/CommandLineTools/usr/bin/git",
                                       "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
                                       "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// True only when the folder sits in a git repo that ignores it.
    private static func isIgnoredByGit(_ folder: URL) -> Bool {
        guard let git else { return false }
        let process = Process()
        process.executableURL = URL(filePath: git)
        process.arguments = ["-C", folder.deletingLastPathComponent().path, "check-ignore", "-q", folder.lastPathComponent]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// A rebuildable folder can still contain committed files. Never offer it if Git tracks anything inside.
    private static func hasTrackedFiles(_ folder: URL) -> Bool {
        guard let git else { return false }
        let process = Process()
        process.executableURL = URL(filePath: git)
        process.arguments = ["-C", folder.deletingLastPathComponent().path, "ls-files", "--cached", "--", folder.lastPathComponent]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty
    }
}
