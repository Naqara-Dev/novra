import SwiftUI

@MainActor @Observable
final class SmartScanModel {
    enum Phase { case idle, scanning, results, cleaning }

    var phase: Phase = .idle
    var progress: Double = 0
    var currentPath = ""
    var currentKind: JunkKind?
    var completed: Set<JunkKind> = []
    var groups: [JunkGroup] = []
    var selected: Set<String> = []
    var expanded: Set<JunkKind> = []
    var report: CleanReport?

    private var task: Task<Void, Never>?

    var found: Int64 { groups.map(\.total).sum }
    var selectedItems: [JunkItem] { groups.flatMap(\.items).filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.map(\.size).sum }

    private var generation = 0

    func scan() {
        task?.cancel()
        generation += 1
        groups = []
        completed = []
        selected = []
        expanded = []
        report = nil
        progress = 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .scanning }
        task = Task {
            var claimed = Set<String>()
            let open = await OpenFilesCache.shared.current()
            // Specific categories first, so the generic cache sweep skips what they already counted.
            let order: [JunkKind] = [.browsers, .developer, .projects, .caches, .clutter, .logs, .system, .leftovers, .installers, .mail, .review, .trash]
            for (index, kind) in order.enumerated() {
                if Task.isCancelled { return }
                currentKind = kind
                let base = Double(index) / Double(order.count)
                let step = 1 / Double(order.count)
                let snapshot = claimed
                let generation = self.generation
                let items = await runDetached { [self] in
                    JunkScanner.scan(kind, claimed: snapshot, open: open) { path, fraction in
                        Task { @MainActor in
                            guard self.phase == .scanning, self.generation == generation else { return }
                            self.currentPath = path
                            self.progress = max(self.progress, base + step * fraction)
                        }
                    }
                }
                if Task.isCancelled { return }
                for item in items { claimed.formUnion(item.urls.map { $0.standardizedFileURL.path }) }
                if !items.isEmpty {
                    groups.append(JunkGroup(kind: kind, items: items))
                    selected.formUnion(items.filter(\.selectedByDefault).map(\.id))
                }
                completed.insert(kind)
                progress = base + step
            }
            groups.sort { JunkKind.allCases.firstIndex(of: $0.kind)! < JunkKind.allCases.firstIndex(of: $1.kind)! }
            currentKind = nil
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .results }
        }
    }

    func cancel() {
        task?.cancel()
        generation += 1
        phase = groups.isEmpty ? .idle : .results
    }

    func size(of kind: JunkKind) -> Int64? {
        groups.first { $0.kind == kind }?.total
    }

    func state(of group: JunkGroup) -> CheckState {
        let count = group.items.filter { selected.contains($0.id) }.count
        return count == 0 ? .off : count == group.items.count ? .on : .mixed
    }

    func toggle(_ group: JunkGroup) {
        let ids = group.items.map(\.id)
        if state(of: group) == .on { selected.subtract(ids) } else { selected.formUnion(ids) }
    }

    func toggle(_ item: JunkItem) {
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    /// Never show this item again.
    func ignore(_ item: JunkItem) {
        Prefs.ignore(item.urls)
        withAnimation(.snappy) {
            for index in groups.indices { groups[index].items.removeAll { $0.id == item.id } }
            groups.removeAll { $0.items.isEmpty }
            selected.remove(item.id)
        }
    }

    func clean(toTrash: Bool) {
        let items = selectedItems
        phase = .cleaning
        Task {
            var targets: [URL: Int64] = [:]
            for item in items {
                // Spread the item's size over its folders so totals stay honest.
                let share = item.size / Int64(max(item.urls.count, 1))
                for url in item.urls { targets[url] = share }
            }
            let result = await Cleaner.remove(targets, toTrash: toTrash, source: "Smart Scan")
            report = result
            let removed = Set(items.filter { item in item.urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }.map(\.id))
            withAnimation(.snappy) {
                for index in groups.indices { groups[index].items.removeAll { removed.contains($0.id) } }
                groups.removeAll { $0.items.isEmpty }
                selected.subtract(removed)
                phase = .results
            }
        }
    }

    func emptyTrash() {
        Task {
            _ = await Cleaner.emptyTrash()
            report?.movedToTrash = false
            groups.removeAll { $0.kind == .trash }
        }
    }
}
