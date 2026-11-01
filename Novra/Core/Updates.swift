import SwiftUI

/// Asks GitHub, at most once a day, whether a newer Novra exists. Sends nothing about the user or the Mac.
@MainActor @Observable
final class Updates {
    static let shared = Updates()

    struct Release: Equatable {
        let version: String
        let page: URL
        let download: URL?
    }

    /// Where an in-place update is. The updater reports it; the update card draws it.
    enum Phase: Equatable {
        case idle
        case preparing
        case downloading(received: Int64, total: Int64)
        case verifying
        case ready
        case installing
        case failed(String)
    }

    var available: Release?
    var checking = false
    var phase: Phase = .idle
    /// Set by the updater (Sparkle): start an in-place update, stop it, or quit into the new version.
    /// Without an installer, Update opens the release on GitHub.
    var installer: (@MainActor () -> Void)?
    var cancelUpdate: (@MainActor () -> Void)?
    var restartToUpdate: (@MainActor () -> Void)?

    var isUpdating: Bool {
        switch phase {
        case .idle, .failed: false
        default: true
        }
    }

    /// One line for the current phase, for places without room for the full card.
    var phaseSummary: String? {
        switch phase {
        case .idle: nil
        case .preparing: String(localized: "Preparing the update…")
        case .downloading(let received, let total):
            total > 0 ? String(localized: "Downloading… \(Int(Double(received) / Double(total) * 100))%")
                      : String(localized: "Downloading…")
        case .verifying: String(localized: "Verifying the update…")
        case .ready: String(localized: "Ready to install")
        case .installing: String(localized: "Installing…")
        case .failed(let reason): reason
        }
    }
    /// Last outcome, shown in Settings › About.
    var status: String?

    private static let api = URL(string: "https://api.github.com/repos/Naqara-Dev/novra/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedVersion"
    private var loop: Task<Void, Never>?

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Checks on launch when due, then keeps checking while Novra stays open.
    func start() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                await checkIfDue()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func checkIfDue() async {
        guard Prefs.checkForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > 24 * 3600 else { return }
        await check(manual: false)
    }

    /// Returns the newer release, if any. A manual check ignores "skip this version".
    @discardableResult
    func check(manual: Bool) async -> Release? {
        checking = true
        defer { checking = false }
        var request = URLRequest(url: Self.api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Novra/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        // An ephemeral session keeps no cookies or cache between checks.
        let session = URLSession(configuration: .ephemeral)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            status = String(localized: "Couldn't reach GitHub. Try again later.")
            return nil
        }
        UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let dmg = (json["assets"] as? [[String: Any]])?
            .first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }?["browser_download_url"] as? String
        let release = Release(version: version, page: page, download: dmg.flatMap(URL.init(string:)))

        guard Self.isNewer(version, than: Self.currentVersion) else {
            available = nil
            status = String(localized: "You're up to date (version \(Self.currentVersion)).")
            return nil
        }
        status = String(localized: "Novra \(version) is available.")
        if manual || UserDefaults.standard.string(forKey: Self.skippedKey) != version {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { available = release }
        }
        return release
    }

    func skip() {
        guard let version = available?.version else { return }
        UserDefaults.standard.set(version, forKey: Self.skippedKey)
        withAnimation(.snappy) { available = nil }
    }

    func download() {
        if let installer { return installer() }
        guard let release = available else { return }
        NSWorkspace.shared.open(release.download ?? release.page)
    }

    /// Compares dotted versions numerically: 1.10 is newer than 1.9, 1.1 equals 1.1.0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Menu command: check now and say what happened.
    func checkFromMenu() {
        Task {
            let release = await check(manual: true)
            let alert = NSAlert()
            if let release {
                alert.messageText = String(localized: "Novra \(release.version) is available")
                alert.informativeText = installer != nil
                    ? String(localized: "You have version \(Self.currentVersion). Novra downloads it and restarts when you're ready, keeping its permissions.")
                    : String(localized: "You have version \(Self.currentVersion). Download the new version from GitHub?")
                alert.addButton(withTitle: installer != nil ? String(localized: "Update") : String(localized: "Download"))
                alert.addButton(withTitle: String(localized: "Later"))
                if alert.runModal() == .alertFirstButtonReturn { download() }
            } else {
                alert.messageText = status ?? ""
                alert.runModal()
            }
        }
    }
}
