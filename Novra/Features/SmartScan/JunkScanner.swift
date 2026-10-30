import SwiftUI

enum JunkKind: String, CaseIterable, Identifiable, Sendable {
    case caches, browsers, developer, projects, clutter, logs, system, leftovers, installers, mail, review, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: String(localized: "App Caches")
        case .browsers: String(localized: "Browser Cache")
        case .developer: String(localized: "Developer Junk")
        case .projects: String(localized: "Project Build Files")
        case .clutter: String(localized: "System Clutter")
        case .review: String(localized: "Worth a Look")
        case .system: String(localized: "System Junk")
        case .logs: String(localized: "Logs & Crash Reports")
        case .leftovers: String(localized: "Leftovers of Deleted Apps")
        case .installers: String(localized: "Old Installers")
        case .mail: String(localized: "Mail Attachments")
        case .trash: String(localized: "Trash")
        }
    }

    /// One-word label for the scan dial.
    var shortTitle: String {
        switch self {
        case .caches: String(localized: "Caches")
        case .browsers: String(localized: "Browsers")
        case .developer: String(localized: "Developer")
        case .projects: String(localized: "Projects")
        case .clutter: String(localized: "Clutter")
        case .review: String(localized: "Review")
        case .system: String(localized: "System")
        case .logs: String(localized: "Logs")
        case .leftovers: String(localized: "Leftovers")
        case .installers: String(localized: "Installers")
        case .mail: String(localized: "Mail")
        case .trash: String(localized: "Trash")
        }
    }

    var subtitle: String {
        switch self {
        case .caches: String(localized: "Temporary files apps rebuild on their own.")
        case .browsers: String(localized: "Cached web pages and scripts. Close browsers first for the best result.")
        case .developer: String(localized: "Xcode builds, simulator caches and package-manager downloads.")
        case .projects: String(localized: "node_modules, build and dist folders in projects you haven't touched lately.")
        case .clutter: String(localized: "Old window states, broken downloads, firmware files and old crash reports.")
        case .review: String(localized: "Big things that are yours: backups, emulators, AI models. Never ticked for you.")
        case .system: String(localized: "Old system logs, diagnostics and caches outside your user folder. Asks for your password.")
        case .logs: String(localized: "Diagnostic logs nobody reads.")
        case .leftovers: String(localized: "Files left behind by apps that are no longer on this Mac. Review before removing.")
        case .installers: String(localized: "Disk images and packages in Downloads and Desktop.")
        case .mail: String(localized: "Copies of attachments you opened in Mail.")
        case .trash: String(localized: "Already in the Trash. These are deleted for good.")
        }
    }

    /// What changes for the person after cleaning this, in plain words.
    var impact: String {
        switch self {
        case .caches: String(localized: "Apps may open a little slower the first time while they rebuild these. Settings, documents and sign-ins stay.")
        case .browsers: String(localized: "Sites load a bit slower on the first visit. You stay signed in: cookies, passwords, history and bookmarks are untouched.")
        case .developer: String(localized: "The next build takes longer and package managers download dependencies again. Your projects and code are untouched.")
        case .projects: String(localized: "Run npm install, pod install or a build again the next time you open that project. Source code is never touched, and anything tracked in git is skipped.")
        case .clutter: String(localized: "Apps open fresh instead of restoring old windows. Unfinished downloads would need downloading again.")
        case .review: String(localized: "These hold real data: phone backups, emulator disks, downloaded models. Removing one means restoring, recreating or re-downloading it.")
        case .system: String(localized: "Nothing changes for you; macOS keeps writing fresh logs. Old diagnostics are only useful to Apple support. macOS asks for your password once.")
        case .logs: String(localized: "Nothing changes for you. Keep them only if you're investigating a crash right now.")
        case .leftovers: String(localized: "These belong to apps that are gone. If you reinstall one later, it starts with fresh settings.")
        case .installers: String(localized: "Installed apps keep working. You'd download the installer again to reinstall.")
        case .mail: String(localized: "Attachments stay inside your emails. Only copies saved when you opened them are removed.")
        case .trash: String(localized: "Deleted for good. You can't restore these afterwards.")
        }
    }

    var icon: String {
        switch self {
        case .caches: "square.stack.3d.up"
        case .browsers: "globe"
        case .developer: "hammer"
        case .projects: "folder.badge.gearshape"
        case .clutter: "wand.and.stars"
        case .review: "eye"
        case .system: "gearshape.2"
        case .logs: "doc.text.magnifyingglass"
        case .leftovers: "puzzlepiece.extension"
        case .installers: "shippingbox"
        case .mail: "paperclip"
        case .trash: "trash"
        }
    }

    var tint: Color {
        switch self {
        case .caches: Theme.accent
        case .browsers: Color(hex: 0x37B6FF)
        case .developer: Theme.purple
        case .projects: Color(hex: 0x0EA5A4)
        case .clutter: Color(hex: 0xA9B8FF)
        case .review: Color(hex: 0xFFB547)
        case .system: Color(hex: 0x8E9BC7)
        case .logs: Color(hex: 0x8E9BC7)
        case .leftovers: Theme.orange
        case .installers: Color(hex: 0xC48A5A)
        case .mail: Color(hex: 0x4FC3A1)
        case .trash: Theme.red
        }
    }
}

struct JunkItem: Identifiable, Hashable, Sendable {
    var id: String { urls.first?.path ?? name }
    let name: String
    let note: String?
    let urls: [URL]
    let size: Int64
    let selectedByDefault: Bool
}

struct JunkGroup: Identifiable, Sendable {
    let kind: JunkKind
    var items: [JunkItem]
    var id: JunkKind { kind }
    var total: Int64 { items.map(\.size).sum }
}

/// Finds removable junk, one category at a time. Items found by an earlier category are never counted again.
enum JunkScanner {
    typealias Progress = @Sendable (_ path: String, _ fraction: Double) -> Void

    static let home = Cleaner.home
    static let library = home.appending(path: "Library")
    static let caches = library.appending(path: "Caches")

    /// Caches that belong to the system and are better left alone.
    static let protectedCaches: Set<String> = [
        "com.apple.bird", "CloudKit", "com.apple.akd", "com.apple.nsurlsessiond", "com.apple.containermanagerd",
        "FamilyCircle", "com.apple.HomeKit", "com.apple.homed", "com.apple.ap.adprivacyd", "com.apple.iCloudHelper",
        "com.apple.findmy.fmipcore", "com.apple.icloud.fmfd", "com.apple.passd", "GeoServices",
        "com.apple.private.translation", "com.apple.amsengagementd", "com.apple.appstoreagent",
        Bundle.main.bundleIdentifier ?? "com.naqara.novra.mac",
    ]

    static func scan(_ kind: JunkKind, claimed: Set<String>, open: OpenFiles = .empty, progress: Progress) -> [JunkItem] {
        let items: [JunkItem]
        switch kind {
        case .caches: items = scanCaches(claimed: claimed, progress: progress)
        case .browsers: items = scanBrowsers(progress: progress) + ExtraScanners.oldBrowserVersions() + ExtraScanners.chromiumClones()
            + rules(CleanupRules.browsers, claimed, progress)
        case .developer: items = scanDeveloper(progress: progress) + ExtraScanners.oldToolVersions()
            + ExtraScanners.obsoleteEditorExtensions() + rules(CleanupRules.developer, claimed, progress)
        case .projects: items = ProjectScanner.scan(progress: progress)
        case .clutter:
            items = scanClutter(progress: progress) + ExtraScanners.dsStoreFiles(progress: progress)
                + rules(CleanupRules.clutter, claimed, progress)
                + (SystemInfo.hasFullDiskAccess ? rules(CleanupRules.protectedClutter, claimed, progress) : [])
        case .system: items = rules(CleanupRules.system, claimed, progress)
        case .review: items = scanReview(claimed: claimed, progress: progress) + rules(CleanupRules.review, claimed, progress)
        case .logs: items = scanChildren(of: [library.appending(path: "Logs")], claimed: claimed, progress: progress)
        case .leftovers: items = scanLeftovers(claimed: claimed, progress: progress)
        case .installers: items = scanInstallers(progress: progress) + ExtraScanners.installerArchives(progress: progress)
        case .mail: items = scanChildren(of: [library.appending(path: "Containers/com.apple.mail/Data/Library/Mail Downloads")], claimed: claimed, progress: progress)
        case .trash: items = scanChildren(of: [Cleaner.trashFolder], claimed: claimed, progress: progress)
        }
        // Two rules in one category can match the same file; keep it in the first row only.
        var seen = Set<String>()
        let unique = items.compactMap { item -> JunkItem? in
            let kept = item.urls.filter { url in
                let path = url.standardizedFileURL.path
                guard !seen.contains(path), !seen.contains(where: { path.hasPrefix($0 + "/") }) else { return false }
                return true
            }
            kept.forEach { seen.insert($0.standardizedFileURL.path) }
            if kept.count == item.urls.count { return item }
            if kept.isEmpty { return nil }
            let share = item.size / Int64(max(item.urls.count, 1))
            return JunkItem(name: item.name, note: item.note, urls: kept, size: share * Int64(kept.count),
                            selectedByDefault: item.selectedByDefault)
        }
        let ignored = Prefs.ignored
        return unique.compactMap { item -> JunkItem? in
            guard !ignored.isEmpty else { return item }
            let kept = item.urls.filter { !Prefs.isIgnored($0, in: ignored) }
            if kept.count == item.urls.count { return item }
            if kept.isEmpty { return nil }
            // Some folders of this row are ignored: keep the rest, sized proportionally.
            let share = item.size / Int64(max(item.urls.count, 1))
            return JunkItem(name: item.name, note: item.note, urls: kept, size: share * Int64(kept.count),
                            selectedByDefault: item.selectedByDefault)
        }
        .filter { $0.size > 0 }
        // Something a running program has open starts unticked, and says what's using it.
        .map { item -> JunkItem in
            guard let holder = open.holder(ofAny: item.urls) else { return item }
            let inUse = String(localized: "In use by \(holder). Quit it first, or Novra will skip it.")
            return JunkItem(name: item.name, note: item.note.map { "\($0) · \(inUse)" } ?? inUse,
                            urls: item.urls, size: item.size, selectedByDefault: false)
        }
        .sorted { $0.size > $1.size }
    }

    // MARK: Categories

    private static func scanCaches(claimed: Set<String>, progress: Progress) -> [JunkItem] {
        var urls: [URL] = []
        collect(in: caches, claimed: claimed, into: &urls)
        var items = measure(urls, progress: progress) { url in
            let name = url.lastPathComponent
            if let app = SystemInfo.appName(forBundleID: name) { return (app, name) }
            return (name, nil)
        }
        items += electronCaches(claimed: claimed, progress: progress)
        items += rules(CleanupRules.appCaches, claimed, progress)
        // Sandboxed apps keep caches inside their container. Reading other apps' containers
        // without Full Disk Access makes macOS ask for permission, so only look when we have it.
        if SystemInfo.hasFullDiskAccess { items += containerCaches(claimed: claimed, progress: progress) }
        return items
    }

    /// Electron and Chromium-based apps keep rebuildable caches next to their data.
    private static func electronCaches(claimed: Set<String>, progress: Progress) -> [JunkItem] {
        let subfolders = ["Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
                          "GrShaderCache", "ShaderCache", "Crashpad/completed", "Cache/Cache_Data"]
        let support = library.appending(path: "Application Support")
        var items: [JunkItem] = []
        for app in FileSizer.children(of: support) where FileSizer.isDirectory(app) {
            let urls = subfolders.map { app.appending(path: $0) }.filter { url in
                let path = url.standardizedFileURL.path
                return FileManager.default.fileExists(atPath: path)
                    && !claimed.contains(path) && !claimed.contains { path.hasPrefix($0 + "/") }
            }
            guard !urls.isEmpty else { continue }
            progress(app.path, 0.6)
            let size = urls.map { FileSizer.size($0) }.sum
            items.append(JunkItem(name: "\(app.lastPathComponent) web caches", note: "Code, GPU and shader caches",
                                  urls: urls, size: size, selectedByDefault: true))
        }
        return items
    }

    private static func containerCaches(claimed: Set<String>, progress: Progress) -> [JunkItem] {
        var items: [JunkItem] = []
        for container in FileSizer.children(of: library.appending(path: "Containers")) {
            let id = container.lastPathComponent
            guard !id.hasPrefix("com.apple.") else { continue }
            let url = container.appending(path: "Data/Library/Caches")
            let path = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path), !claimed.contains(path) else { continue }
            progress(path, 0.8)
            let size = FileSizer.size(url)
            guard size > 1_000_000 else { continue }
            items.append(JunkItem(name: SystemInfo.appName(forBundleID: id) ?? id, note: "Sandboxed app cache",
                                  urls: [url], size: size, selectedByDefault: true))
        }
        return items
    }

    private static func scanClutter(progress: Progress) -> [JunkItem] {
        let month = Date.now.addingTimeInterval(-30 * 86_400)
        let hourAgo = Date.now.addingTimeInterval(-3_600)
        var items: [JunkItem] = []

        progress(library.appending(path: "Saved Application State").path, 0.1)
        let states = FileSizer.children(of: library.appending(path: "Saved Application State"))
            .filter { (FileSizer.measure($0).lastUsed ?? .distantPast) < month }
        if !states.isEmpty {
            items.append(JunkItem(name: "Old window states", note: "\(states.count) apps not opened in 30+ days",
                                  urls: states, size: states.map { FileSizer.size($0) }.sum, selectedByDefault: true))
        }

        progress(home.appending(path: "Downloads").path, 0.4)
        let partial = FileSizer.children(of: home.appending(path: "Downloads")).filter { url in
            ["download", "crdownload", "part", "partial"].contains(url.pathExtension.lowercased())
                && (FileSizer.measure(url).lastUsed ?? .now) < hourAgo
        }
        for url in partial {
            items.append(JunkItem(name: url.lastPathComponent, note: "Unfinished download", urls: [url],
                                  size: FileSizer.size(url), selectedByDefault: true))
        }

        progress(library.appending(path: "iTunes").path, 0.6)
        for folder in ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"] {
            for url in FileSizer.children(of: library.appending(path: "iTunes/\(folder)")) where url.pathExtension == "ipsw" {
                items.append(JunkItem(name: url.lastPathComponent, note: "Device firmware. Downloaded again if ever needed.",
                                      urls: [url], size: FileSizer.size(url), selectedByDefault: true))
            }
        }

        return items
    }

    /// Large personal data worth knowing about. Shown, never ticked.
    private static func scanReview(claimed: Set<String>, progress: Progress) -> [JunkItem] {
        var candidates: [(String, String, URL)] = [
            ("Docker disk", "Every image, container and volume. Use Toolkit › Docker Cleanup to trim it safely.",
             library.appending(path: "Containers/com.docker.docker/Data/vms")),
            ("Ollama models", "Downloaded AI models", home.appending(path: ".ollama/models")),
            ("LM Studio models", "Downloaded AI models", home.appending(path: ".lmstudio/models")),
            ("Hugging Face cache", "Downloaded models and datasets", home.appending(path: ".cache/huggingface")),
            ("Maven repository", "Java dependencies shared by every Maven and Gradle project", home.appending(path: ".m2/repository")),
            ("NuGet packages", ".NET dependencies", home.appending(path: ".nuget/packages")),
        ]
        for avd in FileSizer.children(of: home.appending(path: ".android/avd")) where avd.pathExtension == "avd" {
            candidates.append(("Emulator: \(avd.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " "))",
                               "Android virtual device and its data", avd))
        }
        for backup in FileSizer.children(of: library.appending(path: "Application Support/MobileSync/Backup")) {
            let info = NSDictionary(contentsOf: backup.appending(path: "Info.plist"))
            let device = info?["Device Name"] as? String ?? "Device"
            let date = (info?["Last Backup Date"] as? Date).map { " from \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
            candidates.append(("\(device) backup", "iPhone or iPad backup\(date)", backup))
        }
        var items: [JunkItem] = []
        for (index, (name, note, url)) in candidates.enumerated() {
            let path = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path), !claimed.contains(path) else { continue }
            progress(path, Double(index) / Double(candidates.count))
            let size = FileSizer.size(url)
            guard size >= 500_000_000 else { continue }
            items.append(JunkItem(name: name, note: note, urls: [url], size: size, selectedByDefault: false))
        }
        return items
    }

    /// Children of `dir`, skipping claimed and protected items. Folders that hold a claimed item are opened
    /// up one level so the rest of their content still counts, without the claimed part.
    private static func collect(in dir: URL, claimed: Set<String>, into urls: inout [URL]) {
        for child in FileSizer.children(of: dir) {
            let name = child.lastPathComponent
            let path = child.standardizedFileURL.path
            if protectedCaches.contains(name) || claimed.contains(path) || name == ".DS_Store" { continue }
            if claimed.contains(where: { $0.hasPrefix(path + "/") }) {
                collect(in: child, claimed: claimed, into: &urls)
            } else {
                urls.append(child)
            }
        }
    }

    private static func scanChildren(of dirs: [URL], claimed: Set<String>, progress: Progress) -> [JunkItem] {
        var urls: [URL] = []
        for dir in dirs { collect(in: dir, claimed: claimed, into: &urls) }
        return measure(urls, progress: progress) { ($0.lastPathComponent, nil) }
    }

    private static func scanBrowsers(progress: Progress) -> [JunkItem] {
        let support = library.appending(path: "Application Support")
        let chromium: [(String, String, String)] = [
            ("Google Chrome", "Google/Chrome", "Google/Chrome"),
            ("Brave", "BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser"),
            ("Microsoft Edge", "Microsoft Edge", "Microsoft Edge"),
            ("Arc", "Arc", "Arc/User Data"),
            ("Vivaldi", "Vivaldi", "Vivaldi"),
            ("Opera", "com.operasoftware.Opera", "com.operasoftware.Opera"),
        ]
        var browsers: [(String, [URL])] = [
            ("Safari", [caches.appending(path: "com.apple.Safari"),
                        library.appending(path: "Containers/com.apple.Safari/Data/Library/Caches")]),
            ("Firefox", [caches.appending(path: "Firefox/Profiles")]),
        ]
        for (name, cacheDir, profileRoot) in chromium {
            var urls = [caches.appending(path: cacheDir)]
            if name == "Arc" { urls.append(caches.appending(path: "company.thebrowser.Browser")) }
            // Per-profile code and GPU caches live outside ~/Library/Caches.
            for profile in FileSizer.children(of: support.appending(path: profileRoot)) where FileSizer.isDirectory(profile) {
                for sub in ["Code Cache", "GPUCache", "Service Worker/CacheStorage"] {
                    urls.append(profile.appending(path: sub))
                }
            }
            browsers.append((name, urls))
        }

        var items: [JunkItem] = []
        for (index, (name, urls)) in browsers.enumerated() {
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { continue }
            progress(existing[0].path, Double(index) / Double(browsers.count))
            let size = existing.map { FileSizer.size($0) }.sum
            items.append(JunkItem(name: name, note: "\(existing.count) cache folder\(existing.count == 1 ? "" : "s")",
                                  urls: existing, size: size, selectedByDefault: true))
        }
        return items
    }

    private static func scanDeveloper(progress: Progress) -> [JunkItem] {
        let dev = library.appending(path: "Developer")
        let entries: [(String, String?, URL, Bool)] = [
            ("Xcode DerivedData", "Build products. Xcode rebuilds them.", dev.appending(path: "Xcode/DerivedData"), true),
            ("Simulator Caches", nil, dev.appending(path: "CoreSimulator/Caches"), true),
            ("Xcode Caches", nil, caches.appending(path: "com.apple.dt.Xcode"), true),
            ("iOS Device Support", "Debug symbols per iOS version. Old ones are safe to remove.", dev.appending(path: "Xcode/iOS DeviceSupport"), false),
            ("Xcode Archives", "Keep archives you may need for crash reports.", dev.appending(path: "Xcode/Archives"), false),
            ("Swift Package Cache", nil, caches.appending(path: "org.swift.swiftpm"), true),
            ("CocoaPods Cache", nil, caches.appending(path: "CocoaPods"), true),
            ("Homebrew Downloads", nil, caches.appending(path: "Homebrew"), true),
            ("npm Cache", nil, home.appending(path: ".npm/_cacache"), true),
            ("Yarn Cache", nil, caches.appending(path: "Yarn"), true),
            ("pnpm Cache", nil, caches.appending(path: "pnpm"), true),
            ("pip Cache", nil, caches.appending(path: "pip"), true),
            ("Go Build Cache", nil, caches.appending(path: "go-build"), true),
            ("Gradle Caches", "Dependencies for every Android/Java project. Re-downloading can take a long time.", home.appending(path: ".gradle/caches"), false),
            ("Android Emulator Cache", nil, home.appending(path: ".android/cache"), true),
            ("Android Build Cache", nil, home.appending(path: ".android/build-cache"), true),
            ("JetBrains Caches", "IDE indexes. Re-indexing a big project takes a while.", caches.appending(path: "JetBrains"), false),
            ("Bun Cache", nil, home.appending(path: ".bun/install/cache"), true),
            ("uv Cache", nil, home.appending(path: ".cache/uv"), true),
            ("Cargo Download Cache", nil, home.appending(path: ".cargo/registry/cache"), true),
            ("Rustup Downloads", nil, home.appending(path: ".rustup/downloads"), true),
            ("Corepack Cache", nil, home.appending(path: ".cache/node/corepack"), true),
            ("node-gyp Headers", nil, caches.appending(path: "node-gyp"), true),
            ("TypeScript Cache", nil, caches.appending(path: "typescript"), true),
            ("Electron Downloads", nil, caches.appending(path: "electron"), true),
            ("Prisma Engines", nil, home.appending(path: ".cache/prisma"), true),
            ("Composer Cache", nil, caches.appending(path: "composer"), true),
            ("XCTest Devices", "Throwaway simulators made by UI tests.", dev.appending(path: "XCTestDevices"), true),
            ("Xcode Products", nil, dev.appending(path: "Xcode/Products"), true),
        ] + FileSizer.children(of: caches.appending(path: "Google"))
            .filter { $0.lastPathComponent.hasPrefix("AndroidStudio") }
            .map { ("\($0.lastPathComponent) Caches", nil, $0, true) }
        var items: [JunkItem] = []
        for (index, (name, note, url, preselect)) in entries.enumerated() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            progress(url.path, Double(index) / Double(entries.count))
            items.append(JunkItem(name: name, note: note ?? url.tildePath, urls: [url],
                                  size: FileSizer.size(url), selectedByDefault: preselect))
        }
        return items
    }

    private static func scanLeftovers(claimed: Set<String>, progress: Progress) -> [JunkItem] {
        progress(library.path, 0)
        let orphans = AppCatalog.build().orphans.filter { entry in
            let path = entry.url.standardizedFileURL.path
            return !claimed.contains(path) && !claimed.contains { path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }
        }
        return orphans.map { entry in
            JunkItem(name: entry.url.lastPathComponent, note: entry.url.deletingLastPathComponent().tildePath,
                     urls: [entry.url], size: FileSizer.size(entry.url), selectedByDefault: false)
        }
    }

    private static func scanInstallers(progress: Progress) -> [JunkItem] {
        let exts: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
        var urls: [URL] = []
        let places = ["Downloads", "Desktop", "Documents", "Public", "Downloads/Telegram Desktop",
                      "Library/Mobile Documents/com~apple~CloudDocs/Downloads"].map { home.appending(path: $0) }
        for dir in places {
            for child in FileSizer.children(of: dir) {
                if exts.contains(child.pathExtension.lowercased()) { urls.append(child) }
            }
        }
        return measure(urls, preselect: false, progress: progress) { ($0.lastPathComponent, $0.deletingLastPathComponent().tildePath) }
    }

    // MARK: Helpers

    private static func rules(_ list: [CleanupRule], _ claimed: Set<String>, _ progress: Progress) -> [JunkItem] {
        list.enumerated().compactMap { index, rule in
            if Task.isCancelled { return nil }
            progress(rule.name, Double(index) / Double(list.count))
            return rule.evaluate(claimed: claimed)
        }
    }

    private static func measure(_ urls: [URL], preselect: Bool = true, progress: Progress,
                                label: (URL) -> (String, String?)) -> [JunkItem] {
        var items: [JunkItem] = []
        for (index, url) in urls.enumerated() {
            if Task.isCancelled { break }
            progress(url.path, Double(index) / Double(max(urls.count, 1)))
            let (name, note) = label(url)
            items.append(JunkItem(name: name, note: note, urls: [url], size: FileSizer.size(url), selectedByDefault: preselect))
        }
        return items
    }
}
