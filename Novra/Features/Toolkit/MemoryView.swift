import SwiftUI
import Darwin

struct AppMemory: Identifiable, Hashable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    let bundleURL: URL?
    let footprint: Int64
}

@MainActor @Observable
final class MemoryModel {
    var total = Int64(ProcessInfo.processInfo.physicalMemory)
    var app: Int64 = 0
    var wired: Int64 = 0
    var compressed: Int64 = 0
    var cached: Int64 = 0
    var free: Int64 = 0
    var apps: [AppMemory] = []
    var selection: Set<pid_t> = []
    var message: String?
    var purging = false
    private var loop: Task<Void, Never>?

    var used: Int64 { app + wired + compressed }
    var pressure: Double { total > 0 ? Double(used) / Double(total) : 0 }

    func start() {
        loop?.cancel()
        loop = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() { loop?.cancel() }

    func refresh() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Int64(getpagesize())
        withAnimation(.easeInOut(duration: 0.6)) {
            app = Int64(stats.internal_page_count - stats.purgeable_count) * page
            wired = Int64(stats.wire_count) * page
            compressed = Int64(stats.compressor_page_count) * page
            cached = Int64(stats.external_page_count + stats.purgeable_count) * page
            free = Int64(stats.free_count) * page
        }

        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        let list = running.map { app -> AppMemory in
            AppMemory(pid: app.processIdentifier, name: app.localizedName ?? "App", bundleURL: app.bundleURL,
                      footprint: Self.footprint(app.processIdentifier))
        }
        .sorted { $0.footprint > $1.footprint }
        withAnimation(.snappy) {
            apps = Array(list.prefix(14))
            selection = selection.filter { pid in apps.contains { $0.pid == pid } }
        }
    }

    /// Memory a process actually holds, the same number Activity Monitor shows.
    private static func footprint(_ pid: pid_t) -> Int64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? Int64(info.ri_phys_footprint) : 0
    }

    func quitSelected() {
        for app in NSWorkspace.shared.runningApplications where selection.contains(app.processIdentifier) {
            app.terminate()
        }
        message = "Asked \(selection.count) app\(selection.count == 1 ? "" : "s") to quit."
        selection = []
    }

    func purge() {
        purging = true
        let before = free
        Task {
            let r = await Shell.runAsAdmin("/usr/sbin/purge")
            refresh()
            purging = false
            message = r.ok ? "Freed about \(max(free - before, 0).byteString) of memory." : "Cancelled."
        }
    }
}

struct MemoryView: View {
    var onBack: () -> Void
    @State private var model = MemoryModel()

    private var segments: [(String, Int64, Color)] {
        [("Apps", model.app, Theme.accent), ("Wired", model.wired, Theme.orange),
         ("Compressed", model.compressed, Theme.purple), ("Cached files", model.cached, Theme.lavender.opacity(0.6)),
         ("Free", model.free, .white.opacity(0.15))]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                IconButton(systemName: "chevron.left", help: "Back to Toolkit", action: onBack)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory").font(.system(size: 22, weight: .bold))
                    Text("Updates live. macOS uses spare memory as cache, so “free” is usually small, and that's fine.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { model.purge() } label: {
                    Label(model.purging ? "Freeing…" : "Free Up RAM", systemImage: "wind")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(model.purging)
            }
            .padding(.horizontal, 28).padding(.top, 22)

            HStack(alignment: .top, spacing: 30) {
                VStack(spacing: 22) {
                    ZStack {
                        ProgressRing(progress: model.pressure, lineWidth: 16,
                                     colors: model.pressure > 0.85 ? Theme.diskColors(0.95) : [Color(hex: 0x0EA5A4), Theme.green, Color(hex: 0x9AF5C8)])
                        VStack(spacing: 4) {
                            Text(model.used.byteString).font(.system(size: 28, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                            Text("used of \(model.total.byteString)").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .frame(width: 230, height: 230)

                    VStack(spacing: 10) {
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(segments, id: \.0) { _, value, color in
                                    Capsule().fill(color)
                                        .frame(width: max(2, geo.size.width * CGFloat(Double(value) / Double(max(model.total, 1)))))
                                }
                            }
                        }
                        .frame(height: 8)
                        ForEach(segments, id: \.0) { name, value, color in
                            HStack {
                                Circle().fill(color).frame(width: 8, height: 8)
                                Text(name).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(value.byteString).font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    .frame(width: 250)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Apps using the most memory").font(.system(size: 13, weight: .semibold))
                    if let message = model.message {
                        Text(message).font(.system(size: 12)).foregroundStyle(Theme.green).transition(.opacity)
                    }
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(model.apps) { app in
                                HStack(spacing: 10) {
                                    CheckBox(isOn: model.selection.contains(app.pid)) {
                                        if model.selection.contains(app.pid) { model.selection.remove(app.pid) } else { model.selection.insert(app.pid) }
                                    }
                                    if let url = app.bundleURL { FileIcon(url: url, size: 24) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.name).font(.system(size: 12.5)).lineLimit(1)
                                        GeometryReader { geo in
                                            Capsule().fill(.white.opacity(0.06)).overlay(alignment: .leading) {
                                                Capsule().fill(Theme.green.gradient)
                                                    .frame(width: geo.size.width * CGFloat(Double(app.footprint) / Double(max(model.apps.first?.footprint ?? 1, 1))))
                                            }
                                        }
                                        .frame(height: 4)
                                    }
                                    SizeLabel(size: app.footprint, tint: .white.opacity(0.85))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card.opacity(0.6)))
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 10)

            SelectionBar(count: model.selection.count, size: 0, actionTitle: "Quit") { model.quitSelected() }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
