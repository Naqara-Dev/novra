#if DEBUG
import Foundation

/// Made-up results for README screenshots, so no real files or project names end up public.
/// Launch with `-demo YES` (Debug builds only).
@MainActor
enum DemoData {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demo") }

    private static let home = Cleaner.home
    private static func days(_ n: Double) -> Date { .now.addingTimeInterval(-n * 86_400) }

    static func fill(_ state: AppState) {
        fillScan(state.scan)
        fillProjects(state.projects)
    }

    private static func item(_ name: String, _ note: String?, _ path: String, _ gb: Double, _ on: Bool = true) -> JunkItem {
        JunkItem(name: name, note: note, urls: [home.appending(path: path)], size: Int64(gb * 1e9), selectedByDefault: on)
    }

    private static func fillScan(_ model: SmartScanModel) {
        let groups: [JunkGroup] = [
            JunkGroup(kind: .caches, items: [
                item("Spotify", "com.spotify.client", "Library/Caches/com.spotify.client", 1.42),
                item("Slack web caches", "Code, GPU and shader caches", "Library/Application Support/Slack/Cache", 0.61),
                item("Figma", "com.figma.Desktop", "Library/Caches/com.figma.Desktop", 0.38),
            ]),
            JunkGroup(kind: .browsers, items: [
                item("Google Chrome", "3 cache folders", "Library/Caches/Google/Chrome", 2.31),
                item("Safari", "1 cache folder", "Library/Caches/com.apple.Safari", 0.74),
            ]),
            JunkGroup(kind: .developer, items: [
                item("Xcode DerivedData", "Build products. Xcode rebuilds them.", "Library/Developer/Xcode/DerivedData", 9.8),
                item("npm Cache", "~/.npm/_cacache", ".npm/_cacache", 2.1),
                item("iOS Device Support", "Debug symbols per iOS version. Old ones are safe to remove.", "Library/Developer/Xcode/iOS DeviceSupport", 6.4, false),
                item("Gradle Caches", "Dependencies for every Android/Java project.", ".gradle/caches", 3.2, false),
            ]),
            JunkGroup(kind: .projects, items: [
                item("acme-web", "node_modules, .next · used 5 months ago · ~/Code", "Code/acme-web/node_modules", 3.9),
                item("landing-page", "node_modules · used 8 months ago · ~/Code", "Code/landing-page/node_modules", 1.2),
                item("mobile-app", "Pods, build · used 2 days ago · ~/Code", "Code/mobile-app/Pods", 2.6, false),
            ]),
            JunkGroup(kind: .logs, items: [item("DiagnosticReports", nil, "Library/Logs/DiagnosticReports", 0.12)]),
            JunkGroup(kind: .leftovers, items: [
                item("com.oldvpn.client", "~/Library/Application Support", "Library/Application Support/com.oldvpn.client", 0.42, false),
                item("com.photoeditor.mac", "~/Library/Containers", "Library/Containers/com.photoeditor.mac", 0.21, false),
            ]),
            JunkGroup(kind: .installers, items: [item("Xcode_26.xip", "~/Downloads", "Downloads/Xcode_26.xip", 7.9, false)]),
            JunkGroup(kind: .trash, items: [item("Old Exports", nil, ".Trash/Old Exports", 1.6)]),
        ]
        model.groups = groups
        model.selected = Set(groups.flatMap(\.items).filter(\.selectedByDefault).map(\.id))
        model.phase = .results
    }

    private static func fillProjects(_ model: ProjectsModel) {
        func project(_ path: String, _ folders: [(String, Double, Double)]) -> ProjectJunk {
            let root = home.appending(path: path)
            return ProjectJunk(project: root, folders: folders.map { name, gb, age in
                ProjectFolder(url: root.appending(path: name), footprint: Footprint(size: Int64(gb * 1e9), lastUsed: days(age)))
            })
        }
        model.projects = [
            project("Code/acme-web", [("node_modules", 2.4, 150), (".next", 1.5, 150)]),
            project("Code/landing-page", [("node_modules", 1.2, 240)]),
            project("Code/analytics-api", [(".venv", 0.9, 95), ("__pycache__", 0.05, 95)]),
            project("Code/ios-widget", [("Pods", 0.7, 130), ("build", 0.6, 130)]),
            project("Code/rust-cli", [("target", 3.1, 200)]),
            project("Code/design-system", [("node_modules", 1.1, 60), ("dist", 0.2, 60)]),
            project("Code/mobile-app", [("node_modules", 1.8, 2), (".expo", 0.3, 2)]),
        ].sorted { $0.size > $1.size }
        model.hasScanned = true
    }
}
#endif
