import SwiftUI

@MainActor @Observable
final class FolderExplorerModel {
    struct Entry: Identifiable, Hashable {
        var id: String { url.path }
        let url: URL
        let isFolder: Bool
    }

    let root: URL
    var path: [URL]
    var entries: [Entry] = []
    var footprints: [String: Footprint] = [:]
    var selection: Set<String> = []
    var report: CleanReport?
    var didRemove = false
    private var task: Task<Void, Never>?

    init(root: URL) {
        self.root = root
        self.path = [root]
    }

    var current: URL { path.last ?? root }

    /// Biggest first. Stored, and re-sorted only when sizes arrive, because views read it on every frame.
    private(set) var sortedEntries: [Entry] = []

    private func resort() {
        sortedEntries = entries.sorted { (footprints[$0.id]?.size ?? -1) > (footprints[$1.id]?.size ?? -1) }
    }

    var selectionSize: Int64 { selection.compactMap { footprints[$0]?.size }.sum }

    func open(_ url: URL) {
        path.append(url)
        load()
    }

    func jump(to index: Int) {
        path = Array(path.prefix(index + 1))
        load()
    }

    func load() {
        task?.cancel()
        selection = []
        let folder = current
        entries = FileSizer.children(of: folder)
            .filter { $0.lastPathComponent != ".DS_Store" }
            .map { Entry(url: $0, isFolder: FileSizer.isDirectory($0)) }
        resort()
        let pending = entries.filter { footprints[$0.id] == nil }.map(\.url)
        task = Task {
            await withTaskGroup(of: (String, Footprint).self) { group in
                var iterator = pending.makeIterator()
                for _ in 0..<6 {
                    guard let url = iterator.next() else { break }
                    group.addTask { (url.path, FileSizer.measure(url)) }
                }
                // Publish results in batches, so the chart animates a few times a second instead of on every folder.
                var batch: [String: Footprint] = [:]
                var lastFlush = ContinuousClock.now
                while let (path, footprint) = await group.next() {
                    if Task.isCancelled { group.cancelAll(); break }
                    batch[path] = footprint
                    if ContinuousClock.now - lastFlush > .milliseconds(250) {
                        flush(&batch)
                        lastFlush = .now
                    }
                    if let url = iterator.next() { group.addTask { (url.path, FileSizer.measure(url)) } }
                }
                flush(&batch)
            }
        }
    }

    private func flush(_ batch: inout [String: Footprint]) {
        guard !batch.isEmpty else { return }
        let ready = batch
        batch = [:]
        withAnimation(.easeOut(duration: 0.35)) {
            footprints.merge(ready) { $1 }
            resort()
        }
    }

    func toggle(_ entry: Entry) {
        if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
    }

    /// Ticks what hasn't been used in 3 months, plus anything Novra knows is unused, but never what's needed.
    func selectStale() {
        selection = Set(entries.filter { entry in
            switch PathHints.insight(for: entry.url)?.tone {
            case .needed: return false
            case .unused, .safe: return true
            case nil: return footprints[entry.id]?.lastUsed?.isStale == true
            }
        }.map(\.id))
    }

    func remove(toTrash: Bool) {
        let targets = Dictionary(uniqueKeysWithValues: selection.map { (URL(filePath: $0), footprints[$0]?.size ?? 0) })
        Task {
            let result = await Cleaner.remove(targets, toTrash: toTrash, source: "Space Lens")
            withAnimation(.snappy) { report = result }
            didRemove = true
            // Parent folders shrank; forget their sizes.
            for url in path { footprints[url.path] = nil }
            for key in targets.keys { footprints[key.path] = nil }
            load()
        }
    }
}

/// Browse inside a folder, biggest first, and pick exactly what to remove.
struct FolderExplorer: View {
    @State private var model: FolderExplorerModel
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss
    var onChange: () -> Void

    init(root: URL, onChange: @escaping () -> Void) {
        _model = State(initialValue: FolderExplorerModel(root: root))
        self.onChange = onChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            if let report = model.report {
                CleanResultBanner(report: report, onEmptyTrash: nil, onDismiss: { model.report = nil })
                    .padding(.horizontal, 20).padding(.top, 12)
            }
            if model.entries.isEmpty {
                EmptyState(icon: "folder", title: "Empty folder", message: "There's nothing inside, or Novra can't read it.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.sortedEntries) { entry in row(entry) }
                    }
                    .padding(12)
                }
            }
            SelectionBar(count: model.selection.count, size: model.selectionSize) { confirming = true }
        }
        .frame(width: 760, height: 580)
        .background(Color(hex: 0x0D1434))
        .overlay { ActivityOverlay() }
        .foregroundStyle(.white)
        .onAppear { model.load() }
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(title: "Remove selected items?", count: model.selection.count,
                                size: model.selectionSize, note: nil) { model.remove(toTrash: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.root.lastPathComponent).font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Select \(Prefs.staleLabel.lowercased())") { model.selectStale() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button("Done") {
                    if model.didRemove { onChange() }
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(model.path.enumerated()), id: \.offset) { index, url in
                        if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.tertiary) }
                        Button(index == 0 ? url.tildePath : url.lastPathComponent) { model.jump(to: index) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: index == model.path.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == model.path.count - 1 ? .white : Theme.secondary)
                    }
                }
            }
            .scrollIndicators(.never)
            if let hint = PathHints.hint(for: model.current) {
                Label(hint, systemImage: "lightbulb").font(.system(size: 12)).foregroundStyle(Theme.lavender)
            }
        }
        .padding(20)
    }

    private func row(_ entry: FolderExplorerModel.Entry) -> some View {
        let footprint = model.footprints[entry.id]
        return HStack(spacing: 12) {
            CheckBox(isOn: model.selection.contains(entry.id)) { model.toggle(entry) }
            FileIcon(url: entry.url, size: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.url.lastPathComponent).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                        .layoutPriority(1)
                    UsageBadge(url: entry.url, lastUsed: footprint?.lastUsed)
                }
                if let hint = PathHints.hint(for: entry.url) {
                    Text(hint).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                } else if let date = footprint?.lastUsed {
                    Text("Last used \(date.relativeString)").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SizeLabel(size: footprint?.size, tint: .white.opacity(0.85))
            IconButton(systemName: "folder", help: "Show in Finder") { SystemInfo.reveal(entry.url) }
            if entry.isFolder {
                IconButton(systemName: "chevron.right", help: "Open") { model.open(entry.url) }
            } else {
                Color.clear.frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card.opacity(0.5)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if entry.isFolder { model.open(entry.url) } }
    }
}
