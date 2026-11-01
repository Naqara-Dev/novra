import AppKit
import CoreServices

struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String?
    let lastUsed: Date?

    var isApple: Bool { bundleID.hasPrefix("com.apple.") }
}

enum RelatedKind: Int, CaseIterable, Comparable, Sendable {
    case bundle, data, caches, containers, preferences, logs, launch, other

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .bundle: String(localized: "Application")
        case .data: String(localized: "App Data")
        case .caches: String(localized: "Caches")
        case .containers: String(localized: "Containers")
        case .preferences: String(localized: "Preferences")
        case .logs: String(localized: "Logs")
        case .launch: String(localized: "Launch Agents")
        case .other: String(localized: "Other Files")
        }
    }

    var icon: String {
        switch self {
        case .bundle: "macwindow"
        case .data: "externaldrive"
        case .caches: "square.stack.3d.up"
        case .containers: "shippingbox"
        case .preferences: "slider.horizontal.3"
        case .logs: "doc.text"
        case .launch: "bolt"
        case .other: "doc"
        }
    }
}

struct RelatedItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let kind: RelatedKind
    /// Shared with other tools or holds the user's own work, so it is not ticked when uninstalling.
    var cautious = false
    let isFolder: Bool

    init(url: URL, kind: RelatedKind, cautious: Bool = false) {
        self.url = url
        self.kind = kind
        self.cautious = cautious
        isFolder = kind != .bundle && FileSizer.isDirectory(url)
    }
}

/// Every installed app, the files each one keeps around the Mac, and files whose app is gone.
struct AppCatalog: Sendable {
    var apps: [InstalledApp] = []
    var related: [String: [RelatedItem]] = [:]
    var orphans: [RelatedItem] = []

    static let home = Cleaner.home

    private static let locations: [(String, RelatedKind)] = [
        ("Library/Application Support", .data),
        ("Library/Caches", .caches), ("Library/HTTPStorages", .caches), ("Library/WebKit", .caches),
        ("Library/Containers", .containers), ("Library/Group Containers", .containers),
        ("Library/Application Scripts", .containers),
        ("Library/Preferences", .preferences), ("Library/Preferences/ByHost", .preferences),
        ("Library/Logs", .logs), ("Library/LaunchAgents", .launch),
        ("Library/Saved Application State", .other), ("Library/Cookies", .other),
    ]

    /// Locations where vendors nest one folder per product, e.g. Application Support/Google/AndroidStudio2025.1.
    private static let vendorLocations: Set<String> = ["Library/Application Support", "Library/Caches", "Library/Logs"]

    /// Folders of ~/Library that belong to macOS, not to any one app.
    private static let systemLibraryFolders: Set<String> = [
        "Accessibility", "Accounts", "Application Scripts", "Application Support", "Assistant", "Assistants",
        "Audio", "Autosave Information", "Biome", "Caches", "Calendars", "CallServices", "CloudStorage",
        "ColorPickers", "Colors", "Compositions", "Containers", "ContainerManager", "Contacts", "Cookies",
        "CoreFollowUp", "Daemon Containers", "DataAccess", "DataDeliveryServices", "Developer", "DES",
        "DoNotDisturb", "DuetExpertCenter", "Favorites", "FontCollections", "Fonts", "FrontBoard", "GameKit",
        "Group Containers", "HomeKit", "HTTPStorages", "IdentityServices", "Input Methods", "Intents",
        "Internet Plug-Ins", "Keyboard", "Keyboard Layouts", "KeyboardServices", "Keychains", "LanguageModeling",
        "LaunchAgents", "Logs", "Mail", "Messages", "Metadata", "Mobile Documents", "Passes", "PersonalizationPortrait",
        "Photos", "PPM", "Preferences", "PrivateCloudCompute", "Reminders", "ResponseKit", "Safari", "SafariSafeBrowsing",
        "Saved Application State", "Screen Savers", "Services", "Sharing", "Shortcuts", "Sounds", "Spelling",
        "Spotlight", "StatusKit", "Suggestions", "SyncedPreferences", "Translation", "Trial", "Weather", "WebKit",
        "com.apple.aiml.instrumentation", "studentd", "Printers", "Group Containers",
    ]

    /// Words too common to tie a file to one app.
    private static let genericWords: Set<String> = [
        "app", "apps", "studio", "desktop", "helper", "pro", "plus", "lite", "free", "the", "for", "mac", "macos",
        "osx", "beta", "canary", "connect", "client", "browser", "editor", "code", "player", "manager", "tools",
        "tool", "toolkit", "launcher", "agent", "service", "services", "com", "org", "net", "io", "dev", "co",
        "inc", "ltd", "software", "update", "updater", "cloud", "mobile", "web", "online", "google", "microsoft",
        "apple", "adobe", "jetbrains", "mozilla", "free", "data", "user", "shared", "library", "support", "mail",
        "notes", "music", "photo", "photos", "video", "chat", "meeting", "remote", "suite", "community", "edition",
        "android", "file", "files", "transfer", "sync", "drive", "studio",
    ]

    /// Frameworks and command-line tools that write under ~/Library without being apps.
    private static let toolVendors = ["org.swift.", "org.sparkle-project.", "com.bugsnag.", "com.crashlytics.",
                                      "io.sentry.", "org.python.", "com.vercel.", "org.nodejs.", "com.github.githubcli"]

    /// Places an app keeps data that no naming rule would find.
    private static let knownExtras: [String: [(path: String, cautious: Bool)]] = [
        "com.google.android.studio": [(".android", true), ("Library/Android", true), (".gradle", true),
                                      (".m2", true), (".emulator_console_auth_token", false), (".skiko", false)],
        "com.apple.dt.Xcode": [("Library/Developer", true)],
        "com.microsoft.VSCode": [(".vscode", false), ("Library/Application Support/Code", false)],
        "com.todesktop.230313mzl4w4u92": [(".cursor", false), ("Library/Application Support/Cursor", false)],
        "com.docker.docker": [(".docker", false)],
        "org.virtualbox.app.VirtualBox": [("VirtualBox VMs", true), ("Library/VirtualBox", false)],
        "com.postmanlabs.mac": [("Postman", true)],
        "com.hnc.Discord": [("Library/Application Support/discord", false)],
        "com.tinyspeck.slackmacgap": [("Library/Application Support/Slack", false)],
        "com.anthropic.claudefordesktop": [("Library/Application Support/Claude", false)],
        "net.portswigger.burp.startburp": [(".BurpSuite", false)],
        "com.dbeaver.product": [("Library/DBeaverData", true)],
    ]

    private struct Candidate {
        let url: URL
        let kind: RelatedKind
        let location: String
        /// Name with prefixes and extensions removed, lowercased: "com.google.chrome".
        let key: String
        /// Lowercased letters and digits only: "bravesoftware".
        let plain: String
        let isReverseDNS: Bool
    }

    // MARK: Build

    static func build() -> AppCatalog {
        var catalog = AppCatalog()
        catalog.apps = listApps()
        var candidates = collectCandidates()
        var claimed = Set<String>()

        func assign(_ c: Candidate, to app: InstalledApp, cautious: Bool = false) {
            guard claimed.insert(c.url.path).inserted else { return }
            catalog.related[app.id, default: []].append(RelatedItem(url: c.url, kind: c.kind, cautious: cautious))
        }

        // 1. Bundle-identifier matches win over everything else. When several apps match
        //    (com.jetbrains.intellij and com.jetbrains.intellij.ce), the most specific one gets the file.
        let byID = catalog.apps.sorted { $0.bundleID.count > $1.bundleID.count }
        for c in candidates {
            if let owner = byID.first(where: { matchesBundleID(c, $0.bundleID.lowercased()) }) { assign(c, to: owner) }
        }
        for app in catalog.apps {
            for extra in knownExtras[app.bundleID] ?? [] {
                let url = home.appending(path: extra.path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let c = Candidate(url: url, kind: .data, location: "", key: "", plain: "", isReverseDNS: false)
                assign(c, to: app, cautious: extra.cautious)
            }
        }

        // 2. Name matches, for third-party apps only.
        for app in catalog.apps where !app.isApple {
            let words = tokens(for: app)
            guard !words.isEmpty else { continue }
            let vendor = vendorName(app.bundleID)
            let appPlain = plainName(app.name)
            for c in candidates where !claimed.contains(c.url.path) {
                if matchesName(c, words: words, appPlain: appPlain) {
                    assign(c, to: app)
                } else if let vendor, vendorLocations.contains(c.location), !c.isReverseDNS,
                          c.plain == vendor || c.plain.hasPrefix(vendor) {
                    // Look one level inside the vendor folder for this product.
                    for child in FileSizer.children(of: c.url) {
                        let childPlain = plainName(child.lastPathComponent)
                        if words.contains(where: { childPlain.contains($0) }) || childPlain == appPlain {
                            assign(Candidate(url: child, kind: c.kind, location: c.location, key: "",
                                             plain: childPlain, isReverseDNS: false), to: app)
                        }
                    }
                }
            }
        }

        for app in catalog.apps {
            catalog.related[app.id]?.sort { ($0.kind, $0.url.lastPathComponent) < ($1.kind, $1.url.lastPathComponent) }
        }

        // 3. Whatever looks like an app's file but has no app left is a leftover.
        candidates.removeAll { claimed.contains($0.url.path) }
        let installedVendors = Set(installedBundleIDs().compactMap { vendorPrefix($0) })
            .union(catalog.apps.compactMap { vendorPrefix($0.bundleID) })
        catalog.orphans = candidates.filter { c in
            guard c.isReverseDNS, c.kind != .launch, c.location != "Library/Preferences/ByHost" else { return false }
            guard !c.key.hasPrefix("com.apple."), !c.key.contains(".apple."), !c.key.hasPrefix("apple") else { return false }
            guard !JunkScanner.protectedCaches.contains(c.url.lastPathComponent) else { return false }
            guard !toolVendors.contains(where: { c.key.hasPrefix($0) }) else { return false }
            guard let vendor = vendorPrefix(c.key), !installedVendors.contains(vendor) else { return false }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: c.key) == nil
        }.map { RelatedItem(url: $0.url, kind: $0.kind) }

        return catalog
    }

    // MARK: Apps

    static func listApps() -> [InstalledApp] {
        var urls: [URL] = []
        for root in [URL(filePath: "/Applications"), home.appending(path: "Applications")] {
            for child in FileSizer.children(of: root) {
                if child.pathExtension == "app" {
                    urls.append(child)
                } else if FileSizer.isDirectory(child), child.lastPathComponent != "Utilities" {
                    urls += FileSizer.children(of: child).filter { $0.pathExtension == "app" }
                }
            }
        }
        return urls.compactMap { url -> InstalledApp? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            // Safari ships with macOS and can't be removed.
            if id == "com.apple.Safari" || url.resolvingSymlinksInPath().path.hasPrefix("/System/") { return nil }
            let info = bundle.infoDictionary ?? [:]
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return InstalledApp(url: url, name: name, bundleID: id,
                                version: info["CFBundleShortVersionString"] as? String,
                                lastUsed: lastUsedDate(url))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// When the app was last opened: Spotlight's record, or else when its program file was last read.
    static func lastUsedDate(_ url: URL) -> Date? {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return date
        }
        let executable = Bundle(url: url)?.executableURL
        return (try? executable?.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
    }

    /// Bundle IDs of every app on the Mac, including the ones macOS ships with.
    private static func installedBundleIDs() -> [String] {
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications",
                     "/System/Applications/Utilities", "/System/Library/CoreServices",
                     home.appending(path: "Applications").path]
        var ids: [String] = []
        for root in roots {
            for child in FileSizer.children(of: URL(filePath: root)) {
                let apps = child.pathExtension == "app" ? [child] : FileSizer.children(of: child).filter { $0.pathExtension == "app" }
                ids += apps.compactMap { Bundle(url: $0)?.bundleIdentifier }
            }
        }
        return ids
    }

    // MARK: Candidates

    private static func collectCandidates() -> [Candidate] {
        var result: [Candidate] = []
        for (location, kind) in locations {
            for url in FileSizer.children(of: home.appending(path: location)) {
                let name = url.lastPathComponent
                if name == ".DS_Store" || (location == "Library/Preferences" && name == "ByHost") { continue }
                result.append(candidate(url, kind: kind, location: location))
            }
        }
        // Folders right inside ~/Library, like ~/Library/Android.
        for url in FileSizer.children(of: home.appending(path: "Library"))
        where !systemLibraryFolders.contains(url.lastPathComponent) && !url.lastPathComponent.hasPrefix(".") {
            result.append(candidate(url, kind: .data, location: "Library"))
        }
        // Hidden folders in the home folder, like ~/.android.
        let keepHidden: Set<String> = [".Trash", ".ssh", ".gnupg", ".config", ".local", ".cache", ".zsh_sessions",
                                       ".CFUserTextEncoding", ".DS_Store", ".zshrc", ".bashrc", ".zprofile", ".profile",
                                       ".bash_profile", ".gitconfig", ".bash_history", ".zsh_history", ".lesshst"]
        for url in FileSizer.children(of: home)
        where url.lastPathComponent.hasPrefix(".") && !keepHidden.contains(url.lastPathComponent) {
            result.append(candidate(url, kind: .data, location: "~"))
        }
        return result
    }

    private static func candidate(_ url: URL, kind: RelatedKind, location: String) -> Candidate {
        var key = url.lastPathComponent
        for ext in [".plist", ".savedState", ".binarycookies"] where key.hasSuffix(ext) {
            key = String(key.dropLast(ext.count))
        }
        if key.hasPrefix("group.") { key = String(key.dropFirst(6)) }
        // Group containers often start with a 10-character team ID: "UBF8T346G9.com.microsoft.teams".
        if let dot = key.firstIndex(of: "."), key.distance(from: key.startIndex, to: dot) == 10,
           key[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            key = String(key[key.index(after: dot)...])
        }
        key = key.lowercased()
        let parts = key.split(separator: ".")
        let isReverseDNS = parts.count >= 3 && ["com", "org", "net", "io", "dev", "co", "app", "de", "me", "ru", "us", "uk", "jp", "cn", "info", "ai", "tv", "fr", "nl", "it", "ch", "se"].contains(String(parts[0]))
        return Candidate(url: url, kind: kind, location: location, key: key,
                         plain: plainName(url.lastPathComponent), isReverseDNS: isReverseDNS)
    }

    // MARK: Matching

    private static func matchesBundleID(_ c: Candidate, _ bid: String) -> Bool {
        c.key == bid || c.key.hasPrefix(bid + ".")
    }

    private static func matchesName(_ c: Candidate, words: Set<String>, appPlain: String) -> Bool {
        if c.isReverseDNS {
            // "com.foo.bar": the vendor part ("foo") is shared by all of a vendor's apps, so it doesn't count.
            let parts = c.key.split(separator: ".").dropFirst(2).map(String.init)
            return parts.contains { words.contains($0) }
        }
        let plain = c.plain
        if plain == appPlain || words.contains(plain) { return true }
        return words.contains { $0.count >= 5 && plain.hasPrefix($0) }
    }

    private static func tokens(for app: InstalledApp) -> Set<String> {
        let nameWords = app.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let idWords = app.bundleID.lowercased().split(separator: ".").dropFirst(2).map(String.init)
        return Set((nameWords + idWords).filter { $0.count >= 4 && !genericWords.contains($0) && Int($0) == nil })
    }

    private static func plainName(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// "google" for "com.google.Chrome".
    private static func vendorName(_ bundleID: String) -> String? {
        let parts = bundleID.lowercased().split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let vendor = String(parts[1])
        return vendor.count >= 3 && !["apple", "github", "electron"].contains(vendor) ? vendor : nil
    }

    /// "com.google" for "com.google.Chrome".
    private static func vendorPrefix(_ bundleID: String) -> String? {
        let parts = bundleID.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts[0] + "." + parts[1]
    }
}
