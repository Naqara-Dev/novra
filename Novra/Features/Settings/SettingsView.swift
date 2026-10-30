import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            MenuBarSettings().tabItem { Label("Menu Bar & Alerts", systemImage: "menubar.rectangle") }
            IgnoreListSettings().tabItem { Label("Ignore List", systemImage: "eye.slash") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.Key.defaultToTrash) private var toTrash = true
    @AppStorage(Prefs.Key.checkForUpdates) private var checkForUpdates = true
    @AppStorage(Prefs.Key.staleDays) private var staleDays = 90
    @State private var language = Locale.preferredLanguages.first?.hasPrefix("id") == true ? "id" : "en"
    @State private var languageChanged = false

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("When removing", selection: $toTrash) {
                    Text("Move to Trash (recoverable)").tag(true)
                    Text("Delete permanently").tag(false)
                }
                Picker("Call things unused after", selection: $staleDays) {
                    Text("1 month").tag(30)
                    Text("3 months").tag(90)
                    Text("6 months").tag(180)
                    Text("1 year").tag(365)
                }
            } footer: {
                Text("Novra never removes anything without asking. These only change what's ticked and offered by default.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SwiftUI.Section {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
            } footer: {
                Text("Once a day Novra asks GitHub for the latest version number. Nothing about you or your Mac is sent.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SwiftUI.Section {
                Picker("Language", selection: $language) {
                    Text("English").tag("en")
                    Text("Bahasa Indonesia").tag("id")
                }
                .onChange(of: language) { _, new in
                    UserDefaults.standard.set([new], forKey: "AppleLanguages")
                    languageChanged = true
                }
                if languageChanged {
                    HStack {
                        Text("Restart Novra to switch language.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { Relaunch.now() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MenuBarSettings: View {
    @AppStorage(Prefs.Key.menuBarEnabled) private var menuBar = false
    @AppStorage(Prefs.Key.lowDiskAlert) private var lowDiskAlert = false
    @AppStorage(Prefs.Key.lowDiskGB) private var lowDiskGB = 10

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Show Novra in the menu bar", isOn: $menuBar)
            } footer: {
                Text("Disk and memory at a glance, plus Quick Clean. Novra only runs while you keep it open; there's no hidden background service.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SwiftUI.Section {
                Toggle("Warn me when the disk is almost full", isOn: $lowDiskAlert)
                    .onChange(of: lowDiskAlert) { _, on in if on { LowDiskWatcher.requestPermission() } }
                Picker("Warn below", selection: $lowDiskGB) {
                    Text("5 GB").tag(5)
                    Text("10 GB").tag(10)
                    Text("20 GB").tag(20)
                    Text("50 GB").tag(50)
                }
                .disabled(!lowDiskAlert)
            } footer: {
                Text("Checked while Novra is running, at most once every few hours.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct IgnoreListSettings: View {
    @State private var paths: [String] = Array(Prefs.ignored).sorted()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Novra never shows or offers these, in any scan.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            List {
                if paths.isEmpty {
                    Text("Nothing ignored. Use the \(Image(systemName: "eye.slash")) button on any row to add it here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(paths, id: \.self) { path in
                    HStack {
                        FileIcon(url: URL(filePath: path), size: 18)
                        Text(URL(filePath: path).tildePath).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") {
                            Prefs.unignore(path)
                            withAnimation { paths = Array(Prefs.ignored).sorted() }
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            HStack {
                Button("Add Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        Prefs.ignore(panel.urls)
                        paths = Array(Prefs.ignored).sorted()
                    }
                }
                Spacer()
            }
        }
        .padding(20)
    }
}

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image("NovraLogo").resizable().frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Novra").font(.system(size: 22, weight: .bold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Novra finds it. You decide what goes.").font(.system(size: 13, weight: .medium))
            Text("No analytics, no tracking, and your files never leave your Mac. The only connection Novra makes is the optional update check.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            HStack(spacing: 14) {
                Button("Check for Updates") { Task { await Updates.shared.check(manual: true) } }
                    .disabled(Updates.shared.checking)
                Button("GitHub") { SystemInfo.open(SystemInfo.repository) }
                Button("Report an Issue") { SystemInfo.open(SystemInfo.issues) }
                Button("naqara.dev") { SystemInfo.open("https://naqara.dev") }
            }
            if let status = Updates.shared.status {
                HStack(spacing: 8) {
                    Text(status).font(.system(size: 12))
                    if Updates.shared.available != nil {
                        Button("Download") { Updates.shared.download() }.buttonStyle(.link)
                    }
                }
            }
            Text("Novra is open source under the MIT license.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text("Powered by naqara.dev · © 2026 Naqara Dev").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum Relaunch {
    /// Opens a fresh copy of Novra, then quits this one.
    @MainActor static func now() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
