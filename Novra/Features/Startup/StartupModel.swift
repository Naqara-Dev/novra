import SwiftUI

struct StartupItem: Identifiable, Hashable, Sendable {
    enum Scope: String, Sendable { case user = "Runs for you", allUsers = "Runs for all users", system = "Background service", helper = "Privileged helpers" }

    var id: String { plist.path }
    let plist: URL
    let label: String
    let program: String?
    let scope: Scope
    let appName: String?
    let appURL: URL?
    let runsAtLoad: Bool
    /// For privileged helpers: no app owns it and no launch daemon starts it.
    var orphanHelper = false

    /// The program it launches no longer exists, typically because its app was deleted.
    var isBroken: Bool {
        if scope == .helper { return orphanHelper }
        guard let program else { return false }
        return program.hasPrefix("/") && !FileManager.default.fileExists(atPath: program)
    }
}

enum StartupScanner {
    static func scan() -> [StartupItem] {
        let sources: [(URL, StartupItem.Scope)] = [
            (Cleaner.home.appending(path: "Library/LaunchAgents"), .user),
            (URL(filePath: "/Library/LaunchAgents"), .allUsers),
            (URL(filePath: "/Library/LaunchDaemons"), .system),
        ]
        var items: [StartupItem] = []
        for (folder, scope) in sources {
            for url in FileSizer.children(of: folder) where url.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: url) as? [String: Any] ?? [:]
                let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first
                let (name, appURL) = owningApp(label: label, program: program)
                items.append(StartupItem(plist: url, label: label, program: program, scope: scope,
                                         appName: name, appURL: appURL,
                                         runsAtLoad: dict["RunAtLoad"] as? Bool ?? false))
            }
        }
        // Helper tools apps install to do admin work. Their app being gone makes them orphans.
        let launched = Set(items.compactMap(\.program))
        for url in FileSizer.children(of: URL(filePath: "/Library/PrivilegedHelperTools")) {
            let label = url.lastPathComponent
            let (name, appURL) = owningApp(label: label, program: nil)
            var item = StartupItem(plist: url, label: label, program: url.path, scope: .helper,
                                   appName: name, appURL: appURL, runsAtLoad: false)
            item.orphanHelper = appURL == nil && !launched.contains(url.path)
            items.append(item)
        }
        return items.sorted { ($0.isBroken ? 0 : 1, $0.appName ?? $0.label) < ($1.isBroken ? 0 : 1, $1.appName ?? $1.label) }
    }

    /// Finds the app behind a launch item from the program path or the label.
    private static func owningApp(label: String, program: String?) -> (String?, URL?) {
        if let program, let range = program.range(of: ".app/") {
            let appPath = String(program[..<range.lowerBound]) + ".app"
            let url = URL(filePath: appPath)
            return (url.deletingPathExtension().lastPathComponent, url)
        }
        var parts = label.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) {
                return (url.deletingPathExtension().lastPathComponent, url)
            }
            parts.removeLast()
        }
        return (nil, nil)
    }
}

@MainActor @Observable
final class StartupModel {
    var items: [StartupItem] = []
    var selection: Set<String> = []
    var isLoading = false
    var hasLoaded = false
    var report: CleanReport?

    var selectedItems: [StartupItem] { items.filter { selection.contains($0.id) } }

    func loadIfNeeded() { if !hasLoaded { load() } }

    func load() {
        isLoading = true
        hasLoaded = true
        Task {
            items = await Task.detached { StartupScanner.scan() }.value
            selection = selection.filter { id in items.contains { $0.id == id } }
            isLoading = false
        }
    }

    func state(of list: [StartupItem]) -> CheckState {
        let count = list.filter { selection.contains($0.id) }.count
        return count == 0 ? .off : count == list.count ? .on : .mixed
    }

    func toggle(_ list: [StartupItem]) {
        let ids = list.map(\.id)
        if state(of: list) == .on { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    func selectBroken() {
        selection = Set(items.filter(\.isBroken).map(\.id))
    }

    /// Stops the selected items and moves their launch files to the Trash (Cleaner unloads each job
    /// first). Items outside your user folder need your password once.
    func removeSelection() {
        let chosen = selectedItems
        Task {
            let targets = Dictionary(uniqueKeysWithValues: chosen.map { ($0.plist, Int64(0)) })
            var result = await Cleaner.remove(targets, toTrash: true, source: "Startup Items")
            result.freed = 0
            report = result
            let gone = Set(chosen.filter { !FileManager.default.fileExists(atPath: $0.plist.path) }.map(\.id))
            withAnimation(.snappy) {
                items.removeAll { gone.contains($0.id) }
                selection.subtract(gone)
            }
        }
    }
}
