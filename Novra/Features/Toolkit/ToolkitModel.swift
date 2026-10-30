import SwiftUI

@MainActor @Observable
final class ToolkitModel {
    enum Status: Equatable {
        case idle
        case running
        case done(String)
        case failed(String)
    }

    var open: Tool?
    var status: [Tool: Status] = [:]
    /// Short live facts shown on cards, e.g. "3 snapshots" or "12.4 GB reclaimable".
    var facts: [Tool: String] = [:]
    var available: Set<Tool> = Set(Tool.allCases)

    private static let docker = Shell.find(["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
                                            "/Applications/Docker.app/Contents/Resources/bin/docker"])
    private static let xcrun = Shell.find(["/usr/bin/xcrun"])
    private static let brew = Shell.find(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
    private static let nixStore = Shell.find(["/nix/var/nix/profiles/default/bin/nix-store", "/run/current-system/sw/bin/nix-store"])
    private static let quarantineDB = Cleaner.home.appending(path: "Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2").path
    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    func state(_ tool: Tool) -> Status { status[tool] ?? .idle }

    func refreshFacts() {
        if Self.docker == nil { available.remove(.docker) }
        if Self.brew == nil { available.remove(.homebrew) }
        if Self.nixStore == nil { available.remove(.nix) }
        if !FileManager.default.fileExists(atPath: "/Applications/Xcode.app") { available.remove(.simulators) }
        Task {
            let trash = await Task.detached { FileSizer.size(Cleaner.trashFolder) }.value
            facts[.trash] = trash > 0 ? trash.byteString : (SystemInfo.hasFullDiskAccess ? "Empty" : nil)

            let snaps = await Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
            let count = snaps.output.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
            facts[.snapshots] = count == 0 ? "None" : "\(count) snapshot\(count == 1 ? "" : "s")"

            if let docker = Self.docker {
                let df = await Shell.run(docker, ["system", "df", "--format", "{{.Reclaimable}}"])
                if df.ok {
                    facts[.docker] = Self.sumReclaimable(df.output).map { "\($0.byteString) reclaimable" }
                } else {
                    facts[.docker] = "Docker isn't running"
                }
            }

            if let brew = Self.brew {
                let dry = await Shell.run(brew, ["cleanup", "-n", "--prune=30"])
                if let line = dry.output.split(separator: "\n").last(where: { $0.contains("free approximately") }),
                   let amount = line.split(separator: " ").first(where: { $0.hasSuffix("B") && $0.first?.isNumber == true }) {
                    facts[.homebrew] = "\(amount) to free"
                } else {
                    facts[.homebrew] = "Already tidy"
                }
            }

            let ds = await Shell.run("/usr/bin/defaults", ["read", "com.apple.desktopservices", "DSDontWriteUSBStores"])
            facts[.dsStore] = ds.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1" ? "On" : "Off"

            let rows = await Shell.run("/usr/bin/sqlite3", [Self.quarantineDB, "SELECT COUNT(*) FROM LSQuarantineEvent"])
            if rows.ok, let n = Int(rows.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                facts[.quarantine] = n == 0 ? "Empty" : "\(n.formatted()) entries"
            }

            if Self.xcrun != nil && available.contains(.simulators) {
                let list = await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable"])
                let count = list.output.split(separator: "\n").filter { $0.contains("(unavailable") }.count
                facts[.simulators] = count == 0 ? "None" : "\(count) to remove"
            }
        }
    }

    /// Adds up Docker's "1.2GB (45%)" style values.
    private static func sumReclaimable(_ text: String) -> Int64? {
        var total: Double = 0
        for line in text.split(separator: "\n") {
            let value = line.split(separator: " ").first.map(String.init) ?? ""
            let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
            for (suffix, factor) in units where value.hasSuffix(suffix) {
                total += (Double(value.dropLast(suffix.count)) ?? 0) * factor
                break
            }
        }
        return Int64(total)
    }

    /// Removes macOS metadata files from a drive the user picks under /Volumes.
    private static func cleanExternalDrive(log: @escaping @Sendable (String) -> Void) async -> Status {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(filePath: "/Volumes")
        panel.prompt = "Clean This Drive"
        guard panel.runModal() == .OK, let picked = panel.url else { return .idle }
        // "/Volumes/Macintosh HD" is a link to the startup disk, so resolve it and ask the volume what it is.
        let drive = picked.resolvingSymlinksInPath()
        let info = try? drive.resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsRootFileSystemKey])
        guard drive.path.hasPrefix("/Volumes/"), drive.path != "/Volumes", info?.volumeIsRootFileSystem != true,
              info?.volumeIsInternal != true, info?.volumeIsRemovable == true || info?.volumeIsEjectable == true else {
            return .failed(String(localized: "Pick a USB or external drive"))
        }
        log(String(localized: "Cleaning \(drive.lastPathComponent)…"))
        let report = await Task.detached(priority: .userInitiated) { removeMetadata(on: drive, log: log) }.value
        return .done("Removed \(report.removed) files · \(report.freed.byteString)")
    }

    private nonisolated static func removeMetadata(on drive: URL, log: @Sendable (String) -> Void) -> CleanReport {
        var report = CleanReport()
        let skip: Set<String> = [".Trashes", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100"]
        guard let walker = FileManager.default.enumerator(at: drive, includingPropertiesForKeys: nil) else { return report }
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if skip.contains(name) { walker.skipDescendants(); continue }
            guard name.hasPrefix("._") || name == ".DS_Store" || name == ".TemporaryItems" else { continue }
            if name == ".TemporaryItems" { walker.skipDescendants() }
            let size = FileSizer.size(url)
            if (try? FileManager.default.removeItem(at: url)) != nil {
                report.freed += size
                report.removed += 1
                log(url.path.replacingOccurrences(of: drive.path, with: drive.lastPathComponent))
            }
        }
        return report
    }

    /// Moves preference files that no longer parse to the Trash.
    private static func repairPreferences(log: @escaping @Sendable (String) -> Void) async -> Status {
        let broken = await Task.detached { () -> [URL] in
            FileSizer.children(of: Cleaner.home.appending(path: "Library/Preferences")).filter { url in
                guard url.pathExtension == "plist", let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
                return (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil
            }
        }.value
        guard !broken.isEmpty else { return .done("All preference files are healthy") }
        for url in broken {
            log(String(localized: "Damaged: \(url.lastPathComponent) → Trash"))
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        return .done("Moved \(broken.count) damaged file\(broken.count == 1 ? "" : "s") to Trash")
    }

    /// VACUUMs the big SQLite databases of Apple apps that aren't running.
    private static func compactDatabases(log: @escaping @Sendable (String) -> Void) async -> (Status, Int64) {
        guard SystemInfo.hasFullDiskAccess else { return (.failed(String(localized: "Needs Full Disk Access")), 0) }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let home = Cleaner.home
        var targets: [URL] = []
        if !running.contains("com.apple.mail") {
            targets += Glob.expand("~/Library/Mail/V*/MailData/Envelope Index")
        }
        if !running.contains("com.apple.Safari") { targets.append(home.appending(path: "Library/Safari/History.db")) }
        if !running.contains("com.apple.MobileSMS") { targets.append(home.appending(path: "Library/Messages/chat.db")) }
        targets = targets.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !targets.isEmpty else { return (.failed(String(localized: "Quit Mail, Safari and Messages first")), 0) }
        var saved: Int64 = 0
        for db in targets {
            let before = FileSizer.size(db)
            log(String(localized: "Compacting \(db.tildePath)…"))
            _ = await Shell.run("/usr/bin/sqlite3", [db.path, "VACUUM;"])
            let after = FileSizer.size(db)
            log("  \(before.byteString) → \(after.byteString)")
            saved += max(before - after, 0)
        }
        return (.done(String(localized: "Saved \(saved.byteString)")), saved)
    }

    // MARK: Running a tool

    /// What a tool is doing right now, shown live in a sheet.
    struct Run: Identifiable {
        let id = UUID()
        let tool: Tool
        var lines: [String] = []
        var status: Status = .running
        var freed: Int64 = 0
    }

    var activeRun: Run?

    private func log(_ line: String) {
        guard activeRun != nil else { return }
        activeRun?.lines.append(line)
    }

    /// Streams a command's output into the run log.
    private func stream(_ executable: String, _ arguments: [String]) async -> Shell.Result {
        log("$ " + ([URL(filePath: executable).lastPathComponent] + arguments).joined(separator: " "))
        return await Shell.stream(executable, arguments) { line in
            Task { @MainActor in self.log(line) }
        }
    }

    private func admin(_ command: String) async -> Shell.Result {
        log(String(localized: "Waiting for your password…"))
        let result = await Shell.runAsAdmin(command)
        result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.forEach(log)
        return result
    }

    func run(_ tool: Tool) {
        guard state(tool) != .running else { return }
        withAnimation(.snappy) {
            status[tool] = .running
            activeRun = Run(tool: tool)
        }
        Task {
            log(tool.subtitle)
            let (outcome, freed) = await perform(tool)
            withAnimation(.snappy) {
                status[tool] = outcome
                activeRun?.status = outcome
                activeRun?.freed = freed
            }
            if case .done = outcome {
                let lines = activeRun?.lines ?? []
                let report = CleanReport(freed: freed, removed: 1, movedToTrash: false,
                                         items: lines.filter { !$0.hasPrefix("$ ") }.prefix(500).map {
                                             CleanRecord.Item(original: $0, trashed: nil, size: 0)
                                         })
                History.shared.add(source: tool.title, report: report)
            }
            refreshFacts()
        }
    }

    /// Does the work for one tool, logging each step. Returns the outcome and the space it freed.
    private func perform(_ tool: Tool) async -> (Status, Int64) {
        switch tool {
        case .docker:
            guard let docker = Self.docker else { return (.failed(String(localized: "Docker isn't installed")), 0) }
            log(String(localized: "Removing stopped containers, unused networks and dangling images…"))
            let prune = await stream(docker, ["system", "prune", "-f"])
            guard prune.ok else { return (.failed(String(localized: "Is Docker running?")), 0) }
            log(String(localized: "Removing build cache…"))
            let builder = await stream(docker, ["builder", "prune", "-f"])
            let freed = Shell.parseSizes(prune.output + "\n" + builder.output, marker: "reclaimed space")
            return (.done(String(localized: "Freed \(freed.byteString)")), freed)

        case .homebrew:
            guard let brew = Self.brew else { return (.failed(String(localized: "Homebrew isn't installed")), 0) }
            log(String(localized: "Removing old versions and downloads…"))
            let cleanup = await stream(brew, ["cleanup", "--prune=30"])
            log(String(localized: "Removing dependencies nothing needs…"))
            _ = await stream(brew, ["autoremove"])
            let freed = Shell.parseSizes(cleanup.output, marker: "freed approximately")
            return cleanup.ok ? (.done(freed > 0 ? String(localized: "Freed \(freed.byteString)") : String(localized: "Already tidy")), freed)
                              : (.failed(String(localized: "brew cleanup failed")), 0)

        case .nix:
            guard let nix = Self.nixStore else { return (.failed(String(localized: "Nix isn't installed")), 0) }
            let r = await stream(nix, ["--gc"])
            let freed = Shell.parseSizes(r.output, marker: "freed")
            return r.ok ? (.done(String(localized: "Freed \(freed.byteString)")), freed) : (.failed(String(localized: "nix-store failed")), 0)

        case .snapshots:
            let list = await stream("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
            let count = list.output.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
            guard count > 0 else { return (.done(String(localized: "No local snapshots")), 0) }
            let before = SystemInfo.disk().free
            log(String(localized: "Thinning \(count) snapshots…"))
            let r = await admin("/usr/bin/tmutil thinlocalsnapshots / 999999999999 4")
            let freed = max(SystemInfo.disk().free - before, 0)
            return r.ok ? (.done(String(localized: "Snapshots thinned")), freed)
                        : (.failed(r.output.contains("canceled") ? String(localized: "Cancelled") : String(localized: "Couldn't remove snapshots")), 0)

        case .simulators:
            let list = await stream("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable"])
            guard list.output.contains("(unavailable") else { return (.done(String(localized: "Nothing to remove")), 0) }
            log(String(localized: "Deleting the simulators listed above…"))
            let r = await stream("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
            return r.ok ? (.done(String(localized: "Removed")), 0) : (.failed(String(localized: "simctl failed")), 0)

        case .trash:
            let size = await Task.detached { FileSizer.size(Cleaner.trashFolder) }.value
            let items = FileSizer.children(of: Cleaner.trashFolder).filter { $0.lastPathComponent != ".DS_Store" }
            items.prefix(200).forEach { log($0.lastPathComponent) }
            if items.count > 200 { log(String(localized: "and \(items.count - 200) more")) }
            log(String(localized: "Emptying the Trash…"))
            return await Cleaner.emptyTrash() ? (.done(String(localized: "Freed \(size.byteString)")), size)
                                              : (.failed(String(localized: "Couldn't empty the Trash")), 0)

        case .dns:
            let r = await admin("dscacheutil -flushcache; killall -HUP mDNSResponder; arp -a -d")
            return r.ok ? (.done(String(localized: "DNS and ARP caches flushed")), 0) : (.failed(String(localized: "Cancelled")), 0)

        case .spotlight:
            // Your files live on the Data volume; "/" is the sealed system volume. Rebuilding does nothing
            // while indexing is off, so switch it back on first, then check what Spotlight actually reports.
            let data = "/System/Volumes/Data"
            let r = await admin("/usr/bin/mdutil -i on \(data); /usr/bin/mdutil -E \(data)")
            guard r.ok else { return (.failed(String(localized: "Cancelled")), 0) }
            let status = await Shell.run("/usr/bin/mdutil", ["-s", data])
            status.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.forEach(log)
            if status.output.contains("disabled") || status.output.contains("read-only") {
                return (.failed(String(localized: "Spotlight is still off. Check System Settings › Spotlight › Search Privacy.")), 0)
            }
            return (.done(String(localized: "Rebuilding in the background")), 0)

        case .launchServices:
            let r = await stream(Self.lsregister, ["-r", "-domain", "local", "-domain", "system", "-domain", "user"])
            return r.ok ? (.done(String(localized: "Open With menu rebuilt")), 0) : (.failed(String(localized: "lsregister failed")), 0)

        case .quickLook:
            _ = await stream("/usr/bin/qlmanage", ["-r", "cache"])
            let r = await stream("/usr/bin/qlmanage", ["-r"])
            return r.ok ? (.done(String(localized: "Previews reset")), 0) : (.failed(String(localized: "qlmanage failed")), 0)

        case .externalDrive:
            let status = await Self.cleanExternalDrive { line in Task { @MainActor in self.log(line) } }
            return (status, 0)

        case .preferences:
            log(String(localized: "Checking every file in ~/Library/Preferences…"))
            let status = await Self.repairPreferences { line in Task { @MainActor in self.log(line) } }
            return (status, 0)

        case .databases:
            let (status, saved) = await Self.compactDatabases { line in Task { @MainActor in self.log(line) } }
            return (status, saved)

        case .permissions:
            log(String(localized: "This takes a few minutes."))
            let r = await admin("/usr/sbin/diskutil resetUserPermissions / \(getuid())")
            return r.ok ? (.done(String(localized: "Permissions repaired")), 0)
                        : (.failed(r.output.contains("canceled") ? String(localized: "Cancelled") : String(localized: "diskutil failed")), 0)

        case .verifyDisk:
            var r = await stream("/usr/sbin/diskutil", ["verifyVolume", "/"])
            if !r.ok && r.output.contains("ermission") { r = await admin("/usr/sbin/diskutil verifyVolume /") }
            if r.output.contains("appears to be OK") { return (.done(String(localized: "Your disk looks healthy")), 0) }
            return r.ok ? (.done(String(localized: "Check finished")), 0) : (.failed(String(localized: "Problems found. Run First Aid in Disk Utility.")), 0)

        case .maintenance:
            let r = await admin("/usr/sbin/periodic daily weekly monthly")
            return r.ok ? (.done(String(localized: "Maintenance done")), 0) : (.failed(String(localized: "Cancelled")), 0)

        case .dsStore:
            _ = await stream("/usr/bin/defaults", ["write", "com.apple.desktopservices", "DSDontWriteNetworkStores", "-bool", "true"])
            let r = await stream("/usr/bin/defaults", ["write", "com.apple.desktopservices", "DSDontWriteUSBStores", "-bool", "true"])
            return r.ok ? (.done(String(localized: "On after next log in")), 0) : (.failed(String(localized: "Couldn't change the setting")), 0)

        case .quarantine:
            let r = await stream("/usr/bin/sqlite3", [Self.quarantineDB, "DELETE FROM LSQuarantineEvent; VACUUM;"])
            return r.ok ? (.done(String(localized: "History cleared")), 0) : (.failed(String(localized: "Couldn't open the history")), 0)

        case .spaceLens, .memory, .shredder:
            return (.idle, 0)
        }
    }

}
