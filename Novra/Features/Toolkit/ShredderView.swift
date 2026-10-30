import SwiftUI
import UniformTypeIdentifiers

enum Shredder {
    /// Overwrites each file with zeros, then deletes it. Folders are shredded file by file.
    static func shred(_ urls: [URL], step: @Sendable (String, Int64) -> Void) -> CleanReport {
        var report = CleanReport()
        let fm = FileManager.default
        for url in urls {
            let freedBefore = report.freed
            defer { step(url.tildePath, report.freed - freedBefore) }
            guard !Cleaner.isProtected(url), fm.isDeletableFile(atPath: url.path) else { report.failed.append(url); continue }
            let size = FileSizer.size(url)
            var files = [url]
            if FileSizer.isDirectory(url), let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                files = walker.compactMap { $0 as? URL }
            }
            for file in files { overwrite(file) }
            do {
                try fm.removeItem(at: url)
                report.freed += size
                report.removed += 1
            } catch {
                report.failed.append(url)
            }
        }
        return report
    }

    private static func overwrite(_ url: URL) {
        // A cloud placeholder has nothing on disk to overwrite; touching it would only download it.
        var info = stat()
        // Another hard link would lose its content too, so leave those for a plain delete.
        guard lstat(url.path, &info) == 0, info.st_nlink == 1, !FileSizer.isDataless(url),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let length = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        let chunk = Data(count: 1 << 20)
        var written = 0
        while written < length {
            let n = min(chunk.count, length - written)
            try? handle.write(contentsOf: chunk.prefix(n))
            written += n
        }
        try? handle.synchronize()
    }
}

struct ShredderView: View {
    var onBack: () -> Void
    @State private var files: [URL] = []
    @State private var targeted = false
    @State private var confirming = false
    @State private var working = false
    @State private var report: CleanReport?
    @State private var dash: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                IconButton(systemName: "chevron.left", help: "Back to Toolkit", action: onBack)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shredder").font(.system(size: 22, weight: .bold))
                    Text("Overwrites files, then deletes them without going through the Trash.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 28).padding(.top, 22)

            VStack(spacing: 18) {
                dropZone
                if let report {
                    CleanResultBanner(report: report, onEmptyTrash: nil) { withAnimation { self.report = nil } }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !files.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(files, id: \.self) { url in
                                HStack(spacing: 10) {
                                    FileIcon(url: url, size: 24)
                                    Text(url.lastPathComponent).font(.system(size: 12.5)).lineLimit(1)
                                    Text(url.deletingLastPathComponent().tildePath).font(.system(size: 11))
                                        .foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    IconButton(systemName: "xmark", help: "Remove from list") {
                                        withAnimation(.snappy) { files.removeAll { $0 == url } }
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card.opacity(0.6)))
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                        }
                    }
                }
                Label("On SSDs, the strongest protection for deleted data is FileVault. Shredding adds an extra overwrite on top.",
                      systemImage: "info.circle")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            }
            .padding(28)

            Spacer(minLength: 0)
            SelectionBar(count: files.count, size: 0, actionTitle: "Shred", disabled: working) { confirming = true }
        }
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(title: "Shred \(files.count) items?", count: files.count, size: 0,
                                note: "Shredded files cannot be recovered, not even from the Trash.", allowTrashChoice: false) { _ in shred() }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            ToolIcon(tool: .shredder, size: 58)
                .scaleEffect(targeted ? 1.15 : 1)
                .rotationEffect(.degrees(targeted ? -6 : 0))
            Text(targeted ? "Drop to add" : "Drag files or folders here")
                .font(.system(size: 15, weight: .semibold))
            Button("Choose Files…", action: choose).buttonStyle(PillButtonStyle(prominent: false))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(targeted ? Color(hex: 0xFF5A8A).opacity(0.1) : Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(targeted ? Color(hex: 0xFF5A8A) : .white.opacity(0.2),
                              style: StrokeStyle(lineWidth: 1.5, dash: [8, 6], dashPhase: dash))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: targeted)
        .onAppear { withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { dash = -56 } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        withAnimation(.snappy) { if !files.contains(url) { files.append(url) } }
                    }
                }
            }
            return true
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            withAnimation(.snappy) { files += panel.urls.filter { !files.contains($0) } }
        }
    }

    private func shred() {
        let targets = files
        working = true
        Task {
            Activity.shared.begin("Shredding…", total: targets.count)
            let result = await Task.detached(priority: .userInitiated) {
                Shredder.shred(targets) { name, bytes in Task { @MainActor in Activity.shared.step(name, bytes: bytes) } }
            }.value
            await Activity.shared.finish(result)
            withAnimation(.snappy) {
                report = result
                files.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
            }
            working = false
        }
    }
}
