import SwiftUI

@main
struct NovraApp: App {
    @State private var state = AppState()
    @AppStorage(Prefs.Key.menuBarEnabled) private var menuBar = false

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(state)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear { LowDiskWatcher.shared.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Novra on GitHub") { SystemInfo.open(SystemInfo.repository) }
                Button("Report an Issue") { SystemInfo.open(SystemInfo.issues) }
                Divider()
                Button("Novra on naqara.dev") { SystemInfo.open("https://naqara.dev/apps/novra/") }
            }
        }

        Settings {
            SettingsView().preferredColorScheme(.dark)
        }

        MenuBarExtra("Novra", systemImage: "internaldrive", isInserted: $menuBar) {
            MenuBarView().preferredColorScheme(.dark)
        }
        .menuBarExtraStyle(.window)
    }
}

enum Section: String, CaseIterable, Identifiable {
    case scan = "Smart Scan", apps = "Apps", photos = "Photos", projects = "Projects", largeFiles = "Large Files", duplicates = "Duplicates", startup = "Startup Items", toolkit = "Toolkit", history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scan: "gauge.with.dots.needle.33percent"
        case .apps: "square.grid.2x2"
        case .photos: "photo.on.rectangle"
        case .projects: "folder.badge.gearshape"
        case .largeFiles: "doc.viewfinder"
        case .duplicates: "doc.on.doc"
        case .startup: "power"
        case .toolkit: "wrench.and.screwdriver"
        case .history: "clock.arrow.circlepath"
        }
    }
}

@MainActor @Observable
final class AppState {
    var section: Section = .scan
    var disk = SystemInfo.disk()
    var hasFullDiskAccess = SystemInfo.hasFullDiskAccess

    let scan = SmartScanModel()
    let apps = AppsModel()
    let projects = ProjectsModel()
    let photos = PhotosModel()
    let largeFiles = LargeFilesModel()
    let duplicates = DuplicatesModel()
    let startup = StartupModel()
    let toolkit = ToolkitModel()

    init() {
        #if DEBUG
        // Lets a dev build open straight to a page: `open Novra.app --args -startSection Apps -autoScan YES`.
        if let name = UserDefaults.standard.string(forKey: "startSection"), let start = Section(rawValue: name) {
            section = start
        }
        if UserDefaults.standard.bool(forKey: "autoScan") { section == .projects ? projects.scan() : scan.scan() }
        if let tool = UserDefaults.standard.string(forKey: "startTool") { toolkit.open = Tool(rawValue: tool) }
        if DemoData.isOn { DemoData.fill(self) }
        #endif
    }

    func refresh() {
        disk = SystemInfo.disk()
        hasFullDiskAccess = SystemInfo.hasFullDiskAccess
    }
}
