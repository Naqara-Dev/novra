import Foundation

/// One thing Novra knows how to clean, described as a path pattern.
struct CleanupRule: Sendable {
    let name: String
    /// Path with "~" and "*" wildcards. Every match becomes part of one row.
    let paths: [String]
    var olderThanDays: Int? = nil
    var preselect = true
    var note: String? = nil
    /// When set, only children of the matched folders whose names match this pattern count.
    var childPattern: String? = nil

    init(_ name: String, _ paths: String..., olderThanDays: Int? = nil, preselect: Bool = true,
         note: String? = nil, childPattern: String? = nil) {
        self.name = name
        self.paths = paths
        self.olderThanDays = olderThanDays
        self.preselect = preselect
        self.note = note
        self.childPattern = childPattern
    }

    func evaluate(claimed: Set<String>) -> JunkItem? {
        var urls = paths.flatMap(Glob.expand)
        if let childPattern {
            urls = urls.flatMap { FileSizer.children(of: $0).filter { Glob.matches($0.lastPathComponent, childPattern) } }
        }
        urls = urls.filter { url in
            let path = url.standardizedFileURL.path
            return !claimed.contains(path) && !claimed.contains { path.hasPrefix($0 + "/") }
        }
        var size: Int64 = 0
        var kept: [URL] = []
        let cutoff = olderThanDays.map { Date.now.addingTimeInterval(-Double($0) * 86_400) }
        for url in urls {
            let footprint = FileSizer.measure(url)
            if let cutoff, (footprint.lastUsed ?? .distantPast) > cutoff { continue }
            guard footprint.size > 0 else { continue }
            size += footprint.size
            kept.append(url)
        }
        guard !kept.isEmpty, size > 0 else { return nil }
        let age = olderThanDays.map { "older than \($0) day\($0 == 1 ? "" : "s")" }
        let detail = [note, kept.count > 1 ? "\(kept.count) items" : kept[0].tildePath, age].compactMap { $0 }.joined(separator: " · ")
        return JunkItem(name: name, note: detail, urls: kept, size: size, selectedByDefault: preselect)
    }
}

/// Everything beyond the basics, largely following what Mole (github.com/tw93/mole) cleans.
enum CleanupRules {
    private static func userCache(_ name: String) -> String { Glob.userCacheDir.map { $0.path + "/" + name } ?? "" }
    private static func userTemp(_ name: String) -> String { Glob.userTempDir.map { $0.path + "/" + name } ?? "" }
    private static func userClone(_ name: String) -> String { Glob.userCloneDir.map { $0.path + "/" + name } ?? "" }

    static let developer: [CleanupRule] = [
        // Go keeps these warm for every build and editor session; clearing them is safe but slows the
        // next build, and the module cache is read-only on purpose. Off by default.
        CleanupRule("Go Build Cache", "~/Library/Caches/go-build", preselect: false,
                    note: "Go rebuilds it. Your next builds will be slower."),
        CleanupRule("Go Module Cache", "~/go/pkg/mod", preselect: false,
                    note: "Downloaded modules. Go fetches them again when a project needs them."),
        CleanupRule("Go Tool Caches", "~/Library/Caches/golangci-lint", "~/Library/Caches/gopls", "~/Library/Caches/staticcheck",
                    preselect: false, note: "Linter and editor caches. Rebuilt on the next run."),
        CleanupRule("conda Packages", "~/.conda/pkgs", "~/miniconda3/pkgs", "~/anaconda3/pkgs", "~/opt/miniconda3/pkgs",
                    preselect: false, note: "Package downloads. Existing environments keep working."),
        CleanupRule("Poetry Cache", "~/Library/Caches/pypoetry/cache", "~/Library/Caches/pypoetry/artifacts"),
        CleanupRule("pyenv Downloads", "~/.pyenv/cache"),
        CleanupRule("Ruff Cache", "~/.cache/ruff"),
        CleanupRule("mise Cache", "~/Library/Caches/mise"),
        CleanupRule("Ruby Gem Caches", "~/.rbenv/cache", "~/.gem/specs", "~/.local/share/gem/specs", "~/.bundle/cache"),
        CleanupRule("CPAN Build Files", "~/.cpan/build", "~/.cpan/sources"),
        CleanupRule("Hex & Rebar Cache", "~/.hex/packages", "~/.cache/rebar3"),
        CleanupRule("opam Downloads", "~/.opam/download-cache"),
        CleanupRule("Zig Cache", "~/.cache/zig", "~/Library/Caches/zig"),
        CleanupRule("Bazel Cache", "~/.cache/bazel", "~/Library/Caches/bazel", preselect: false,
                    note: "Bazel outputs. The next build starts from scratch."),
        CleanupRule("Terraform Plugin Cache", "~/.terraform.d/plugin-cache"),
        CleanupRule("Docker Buildx Cache", "~/.docker/buildx/cache"),
        CleanupRule("Turborepo Cache", "~/Library/Caches/turbo", "~/.cache/turbo"),
        CleanupRule("Expo Cache", "~/.cache/expo", "~/Library/Caches/expo"),
        CleanupRule("Puppeteer Browsers", "~/.cache/puppeteer", preselect: false, note: "Downloaded test browsers"),
        CleanupRule("Kubernetes Cache", "~/.kube/cache", "~/.kube/http-cache"),
        CleanupRule("AWS CLI Cache", "~/.aws/cli/cache", note: "You may need to sign in to AWS SSO again"),
        CleanupRule("Cloud CLI Logs", "~/.config/gcloud/logs", "~/.azure/logs", "~/.azure/commands"),
        CleanupRule("Vagrant Temp", "~/.vagrant.d/tmp"),
        CleanupRule("Interface Builder Cache", "~/Library/Developer/Xcode/UserData/IB Support"),
        CleanupRule("Other Device Support", "~/Library/Developer/Xcode/macOS DeviceSupport",
                    "~/Library/Developer/Xcode/watchOS DeviceSupport", "~/Library/Developer/Xcode/tvOS DeviceSupport",
                    "~/Library/Developer/Xcode/visionOS DeviceSupport", preselect: false,
                    note: "Debug symbols for watch, TV and Vision devices"),
        CleanupRule("Playwright Leftover Browsers", userTemp("playwright_chromiumdev_profile-*"),
                    olderThanDays: 1, note: "Test browsers left running by crashed tests"),
    ]

    static let appCaches: [CleanupRule] = [
        CleanupRule("Steam Caches", "~/Library/Application Support/Steam/appcache", "~/Library/Application Support/Steam/depotcache",
                    "~/Library/Application Support/Steam/config/htmlcache", "~/Library/Application Support/Steam/steamapps/shadercache"),
        CleanupRule("Minecraft Logs", "~/Library/Application Support/minecraft/logs", "~/Library/Application Support/minecraft/webcache2"),
        CleanupRule("Battle.net Cache", "~/Library/Application Support/Battle.net/Cache"),
        CleanupRule("Adobe Media Cache", "~/Library/Application Support/Adobe/Common/Media Cache Files",
                    "~/Library/Application Support/Adobe/Common/Media Cache",
                    note: "Premiere and After Effects rebuild previews"),
        CleanupRule("DaVinci Resolve Cache", "~/Movies/CacheClip", note: "Render cache. Resolve re-renders when needed."),
        CleanupRule("Dropbox Cache", "~/Dropbox/.dropbox.cache"),
        CleanupRule("GPU Shader Caches", userCache("com.apple.gpuarchiver"),
                    userCache("com.apple.metal"),
                    userCache("com.apple.metalfe"),
                    olderThanDays: 1, note: "Apps recompile shaders on next launch"),
    ]

    static let clutter: [CleanupRule] = [
        CleanupRule("Shell & Tool History Files", "~/.zcompdump*", "~/.lesshst", "~/.viminfo.tmp", "~/.wget-hsts",
                    note: "Rebuilt automatically"),
        CleanupRule("Identity Caches", "~/Library/IdentityCaches", childPattern: "*"),
        CleanupRule("Siri Suggestions Cache", "~/Library/Suggestions", preselect: false,
                    note: "Suggestions start fresh", childPattern: "*"),
        CleanupRule("Contacts Photo Cache", "~/Library/Application Support/AddressBook/Sources/*/Photos.cache",
                    "~/Library/Application Support/AddressBook/Photos.cache"),
        CleanupRule("Recent Items Lists", "~/Library/Application Support/com.apple.sharedfilelist/*Recent*.sfl*",
                    "~/Library/Preferences/com.apple.recentitems.plist", preselect: false,
                    note: "Recent apps, files and servers menus start empty"),
        CleanupRule("Old Crash Reporter Data", "~/Library/Application Support/CrashReporter", olderThanDays: 30, childPattern: "*"),
        CleanupRule("Apple Configurator Firmware",
                    "~/Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Assets/TemporaryItems/MobileAsset",
                    note: "Downloaded again if needed"),
    ]

    /// Only read when Full Disk Access is on, so macOS doesn't ask about other apps' data.
    static let protectedClutter: [CleanupRule] = [
        CleanupRule("Messages Previews & Stickers", "~/Library/Messages/Caches/Previews", "~/Library/Messages/StickerCache",
                    note: "Attachments themselves are kept"),
        CleanupRule("Old Wallpaper Renders", "~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches",
                    olderThanDays: 7, childPattern: "*.bmp"),
        CleanupRule("Handoff Clipboard", "~/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard",
                    olderThanDays: 1, childPattern: "*"),
        CleanupRule("Podcasts Downloads Cache", "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache",
                    preselect: false, note: "Streamed episodes; downloaded ones are kept"),
        CleanupRule("Sandboxed App Temp Files", "~/Library/Containers/*/Data/tmp", olderThanDays: 1, childPattern: "*"),
    ]

    static let system: [CleanupRule] = [
        CleanupRule("System Caches", "/Library/Caches", olderThanDays: 7, childPattern: "*.cache"),
        CleanupRule("System Logs", "/Library/Logs", olderThanDays: 7, childPattern: "*.log"),
        CleanupRule("System Crash Reports", "/Library/Logs/DiagnosticReports", olderThanDays: 7, childPattern: "*"),
        CleanupRule("Unix Logs", "/private/var/log", olderThanDays: 7, childPattern: "*.log"),
        CleanupRule("Adobe System Logs", "/Library/Logs/Adobe", "/Library/Logs/CreativeCloud", "/Library/Logs/adobegc.log"),
        CleanupRule("Diagnostics Data", "/private/var/db/diagnostics", "/private/var/db/DiagnosticPipeline",
                    "/private/var/db/powerlog", olderThanDays: 7, childPattern: "*"),
        CleanupRule("Memory Limit Reports", "/private/var/db/reportmemoryexception/MemoryLimitViolations",
                    olderThanDays: 30, childPattern: "*"),
        CleanupRule("Icon Cache", "/Library/Caches/com.apple.iconservices.store", preselect: false,
                    note: "Icons may look blank until the next restart"),
        CleanupRule("System Simulator Caches", "/Library/Developer/CoreSimulator/Caches",
                    note: "Simulators rebuild this; the first launch afterwards is slower", childPattern: "*"),
        CleanupRule("Xcode Documentation Cache", "/Library/Developer/Xcode/DocumentationCache",
                    "~/Library/Developer/Xcode/DocumentationCache"),
        CleanupRule("Rosetta Update Bundle", "/Library/Apple/usr/share/rosetta/rosetta_update_bundle"),
        CleanupRule("Old macOS Installers", "/Applications/Install macOS*.app", olderThanDays: 14,
                    note: "Download again from the App Store if you need it"),
    ]

    static let browsers: [CleanupRule] = [
        CleanupRule("Dia, Comet, Orion, Zen & Others",
                    "~/Library/Caches/company.thebrowser.dia", "~/Library/Caches/ai.perplexity.comet",
                    "~/Library/Caches/com.kagi.kagimacOS", "~/Library/Caches/zen", "~/Library/Caches/Yandex",
                    "~/Library/Caches/net.imput.helium", "~/Library/Caches/com.tencent.QQBrowser",
                    "~/Library/Application Support/Dia/User Data/*/Code Cache",
                    "~/Library/Application Support/Comet/*/Code Cache"),
        CleanupRule("Chrome On-Device AI Cache", "~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel",
                    "~/Library/Application Support/Google/Chrome/optimization_guide_model_store",
                    preselect: false, note: "Chrome downloads it again if features need it"),
    ]

    static let review: [CleanupRule] = [
        CleanupRule("AI Agent Worktrees", "~/.codex/worktrees", "~/.claude/worktrees", preselect: false,
                    note: "Working copies made by coding agents. Check nothing unmerged is in there.", childPattern: "*"),
    ]
}
