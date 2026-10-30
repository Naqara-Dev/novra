import AppKit

@MainActor @Observable
final class AppsModel {
    enum Sort: String, CaseIterable { case size = "Size", name = "Name", lastUsed = "Last Opened" }
    static let leftoversID = "__leftovers__"

    var apps: [InstalledApp] = []
    var related: [String: [RelatedItem]] = [:]
    var orphans: [RelatedItem] = []
    var footprints: [String: Footprint] = [:]
    var isLoading = false
    var isMeasuring = false
    var hasLoaded = false

    var focusedID: String?
    var selection: Set<String> = []
    var search = ""
    var sort: Sort = .size
    var onlyUnused = false
    var report: CleanReport?
    var runningIDs: Set<String> = []

    private var task: Task<Void, Never>?

    func loadIfNeeded() {
        refreshRunning()
        if !hasLoaded { load() }
    }

    func refreshRunning() {
        runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func isRunning(_ app: InstalledApp) -> Bool { runningIDs.contains(app.bundleID) }

    /// Latest sign of use: open right now, Spotlight's last-opened date, or the app writing to its own data.
    func lastActivity(_ app: InstalledApp) -> Date? {
        if isRunning(app) { return .now }
        let dataDates = (related[app.id] ?? []).filter { !$0.cautious }.compactMap { footprints[$0.id]?.lastUsed }
        return ([app.lastUsed].compactMap { $0 } + dataDates).max()
    }

    func load() {
        task?.cancel()
        isLoading = true
        hasLoaded = true
        refreshRunning()
        task = Task {
            let catalog = await Task.detached(priority: .userInitiated) { AppCatalog.build() }.value
            apps = catalog.apps
            #if DEBUG
            // Screenshots show only well-known apps.
            if DemoData.isOn {
                let shown: Set<String> = ["Xcode", "Google Chrome", "Docker", "Android Studio", "Visual Studio Code", "Slack",
                                          "Spotify", "Figma", "Zoom", "Notion", "Postman", "Discord", "WhatsApp", "Telegram"]
                apps = apps.filter { shown.contains($0.name) }
            }
            #endif
            related = catalog.related
            orphans = catalog.orphans
            isLoading = false
            if focusedID == nil || !apps.contains(where: { $0.id == focusedID }) { focusedID = visibleApps.first?.id }
            await measureAll()
        }
    }

    /// Sizes every app and its files, a few at a time, so the list fills in progressively.
    private func measureAll() async {
        isMeasuring = true
        var queue: [URL] = []
        let ordered = apps.sorted { ($0.id == focusedID ? 0 : 1) < ($1.id == focusedID ? 0 : 1) }
        for app in ordered {
            queue.append(app.url)
            queue += (related[app.id] ?? []).map(\.url)
        }
        queue += orphans.map(\.url)
        queue.removeAll { footprints[$0.path] != nil }

        await withTaskGroup(of: (String, Footprint).self) { group in
            var iterator = queue.makeIterator()
            for _ in 0..<6 {
                guard let url = iterator.next() else { break }
                group.addTask(priority: .utility) { (url.path, FileSizer.measure(url)) }
            }
            var batch: [String: Footprint] = [:]
            var lastFlush = ContinuousClock.now
            while let (path, footprint) = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                batch[path] = footprint
                if ContinuousClock.now - lastFlush > .milliseconds(300) {
                    footprints.merge(batch) { $1 }
                    batch = [:]
                    lastFlush = .now
                }
                if let url = iterator.next() {
                    group.addTask(priority: .utility) { (url.path, FileSizer.measure(url)) }
                }
            }
            footprints.merge(batch) { $1 }
        }
        isMeasuring = false
    }

    // MARK: Queries

    func items(for app: InstalledApp) -> [RelatedItem] {
        [RelatedItem(url: app.url, kind: .bundle)] + (related[app.id] ?? [])
    }


    func total(_ items: [RelatedItem]) -> Int64? {
        var sum: Int64 = 0
        for item in items {
            guard let f = footprints[item.id] else { return nil }
            sum += f.size
        }
        return sum
    }

    func total(for app: InstalledApp) -> Int64? { total(items(for: app)) }

    /// Biggest known size so far, used to sort before everything is measured.
    private func partialTotal(for app: InstalledApp) -> Int64 {
        items(for: app).compactMap { footprints[$0.id]?.size }.sum
    }

    var visibleApps: [InstalledApp] {
        var list = apps
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
        }
        if onlyUnused { list = list.filter { lastActivity($0)?.isStale == true } }
        switch sort {
        case .name: break
        case .size: list.sort { partialTotal(for: $0) > partialTotal(for: $1) }
        case .lastUsed: list.sort { (lastActivity($0) ?? .distantPast) < (lastActivity($1) ?? .distantPast) }
        }
        return list
    }

    var focusedApp: InstalledApp? { apps.first { $0.id == focusedID } }

    // MARK: Selection

    func state(of items: [RelatedItem]) -> CheckState {
        let count = items.filter { selection.contains($0.id) }.count
        return count == 0 ? .off : count == items.count ? .on : .mixed
    }

    func toggle(_ items: [RelatedItem]) {
        let ids = items.map(\.id)
        if state(of: items) == .on { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    /// Ticks everything an uninstall should remove, leaving shared folders for the user to decide.
    func selectForUninstall(_ app: InstalledApp) {
        selection.formUnion(items(for: app).filter { !$0.cautious }.map(\.id))
    }

    var selectionSize: Int64 { selection.compactMap { footprints[$0]?.size }.sum }

    // MARK: Removal

    func removeSelection(toTrash: Bool) {
        let paths = selection
        Task {
            // Quit apps that are about to be uninstalled.
            for app in apps where paths.contains(app.id) {
                for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
                    running.terminate()
                }
            }
            if apps.contains(where: { paths.contains($0.id) }) { try? await Task.sleep(for: .seconds(1.5)) }

            var targets: [URL: Int64] = [:]
            for path in paths { targets[URL(filePath: path)] = footprints[path]?.size ?? 0 }
            let result = await Cleaner.remove(targets, toTrash: toTrash, source: "Apps")
            report = result
            let failed = Set(result.failed.map(\.path))
            let gone = paths.subtracting(failed).filter { !FileManager.default.fileExists(atPath: $0) }
            apps.removeAll { gone.contains($0.id) }
            for key in related.keys { related[key]?.removeAll { gone.contains($0.id) } }
            orphans.removeAll { gone.contains($0.id) }
            selection.subtract(gone)
            if let id = focusedID, id != Self.leftoversID, !apps.contains(where: { $0.id == id }) {
                focusedID = visibleApps.first?.id
            }
        }
    }

    /// Called after the folder explorer removed something inside one of this app's folders.
    func remeasure(_ url: URL) {
        Task {
            let f = await Task.detached { FileSizer.measure(url) }.value
            footprints[url.path] = f
        }
    }

    func emptyTrash() {
        Task {
            _ = await Cleaner.emptyTrash()
            report?.movedToTrash = false
        }
    }
}
