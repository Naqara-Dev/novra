import SwiftUI

/// Scans only the categories that are always safe to clear, for one-click cleaning from the menu bar.
@MainActor @Observable
final class QuickClean {
    enum Phase: Equatable { case idle, scanning, ready, done(Int64) }

    var phase: Phase = .idle
    var items: [JunkItem] = []
    var size: Int64 { items.map(\.size).sum }

    func scan() {
        phase = .scanning
        Task {
            items = await Task.detached(priority: .userInitiated) {
                var claimed = Set<String>()
                var found: [JunkItem] = []
                for kind in [JunkKind.browsers, .caches, .logs, .clutter] {
                    let items = JunkScanner.scan(kind, claimed: claimed) { _, _ in }.filter(\.selectedByDefault)
                    for item in items { claimed.formUnion(item.urls.map { $0.standardizedFileURL.path }) }
                    found += items
                }
                return found
            }.value
            withAnimation(.snappy) { phase = .ready }
        }
    }

    func clean() {
        var targets: [URL: Int64] = [:]
        for item in items {
            let share = item.size / Int64(max(item.urls.count, 1))
            for url in item.urls { targets[url] = share }
        }
        Task {
            let report = await Cleaner.remove(targets, toTrash: Prefs.defaultToTrash, source: "Quick Clean")
            withAnimation(.snappy) { phase = .done(report.freed) }
        }
    }
}

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var disk = SystemInfo.disk()
    @State private var memory = MemoryModel()
    @State private var quick = QuickClean()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image("NovraLogo").resizable().frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Novra").font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    openWindow(id: "main")
                    NSApp.activate()
                } label: { Image(systemName: "macwindow") }
                .buttonStyle(.plain).help("Open Novra")
            }

            HStack(spacing: 14) {
                meter(title: "Disk", value: disk.usedFraction, detail: "\(disk.free.byteString) free",
                      colors: Theme.diskColors(disk.usedFraction))
                meter(title: "Memory", value: memory.pressure, detail: "\(memory.used.byteString) used",
                      colors: memory.pressure > 0.85 ? Theme.diskColors(0.95) : [Color(hex: 0x0EA5A4), Theme.green])
            }

            Group {
                switch quick.phase {
                case .idle:
                    Button { quick.scan() } label: {
                        Label("Quick Clean", systemImage: "bolt").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccentButtonStyle())
                case .scanning:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking for safe junk…") }
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                case .ready:
                    VStack(spacing: 8) {
                        Text(quick.size > 0 ? "Caches, logs and clutter: \(quick.size.byteString)" : "Nothing to clean right now.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        if quick.size > 0 {
                            Button { quick.clean() } label: {
                                Text("Clean \(quick.size.byteString)").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AccentButtonStyle())
                            Text(Prefs.defaultToTrash ? "Goes to the Trash, so you can undo." : "Deleted permanently.")
                                .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                case .done(let freed):
                    Label("Cleaned \(freed.byteString)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green).frame(maxWidth: .infinity)
                        .onTapGesture { quick.phase = .idle }
                }
            }
            .transition(.opacity)

            Divider().overlay(Theme.stroke)
            HStack {
                Button("Open Novra") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
        }
        .padding(16)
        .frame(width: 300)
        .foregroundStyle(.white)
        .background(Color(hex: 0x0B1131))
        .onAppear {
            disk = SystemInfo.disk()
            memory.start()
        }
        .onDisappear { memory.stop() }
    }

    private func meter(title: LocalizedStringKey, value: Double, detail: String, colors: [Color]) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 7)
                Circle().trim(from: 0, to: value)
                    .stroke(AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(value, 0.05))),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value * 100))%").font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(width: 70, height: 70)
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }
}
