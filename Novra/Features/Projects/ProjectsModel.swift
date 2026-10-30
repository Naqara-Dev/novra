import SwiftUI

@MainActor @Observable
final class ProjectsModel {
    enum Age: Int, CaseIterable {
        case month = 30, quarter = 90, half = 180, all = 0

        var label: String {
            switch self {
            case .month: "Unused 1 month+"
            case .quarter: "3 months+"
            case .half: "6 months+"
            case .all: "All"
            }
        }

        func includes(_ date: Date?) -> Bool {
            self == .all || (date ?? .distantPast) < Date.now.addingTimeInterval(-Double(rawValue) * 86_400)
        }
    }

    var projects: [ProjectJunk] = []
    var isScanning = false
    var hasScanned = false
    var progress: Double = 0
    var currentPath = ""
    var age: Age = .month
    var selection: Set<String> = []
    var expanded: Set<String> = []
    var report: CleanReport?
    private var task: Task<Void, Never>?

    var visible: [ProjectJunk] { projects.filter { age.includes($0.lastUsed) } }
    var allFolders: [ProjectFolder] { projects.flatMap(\.folders) }
    var selectionSize: Int64 { allFolders.filter { selection.contains($0.id) }.map(\.footprint.size).sum }
    var visibleSize: Int64 { visible.map(\.size).sum }

    func scan() {
        task?.cancel()
        isScanning = true
        hasScanned = true
        progress = 0
        selection = []
        task = Task {
            let found = await runDetached { [self] in
                ProjectScanner.find { path, fraction in
                    Task { @MainActor in
                        self.currentPath = path
                        self.progress = max(self.progress, fraction)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                projects = found
                isScanning = false
            }
        }
    }

    func state(of project: ProjectJunk) -> CheckState {
        let count = project.folders.filter { selection.contains($0.id) }.count
        return count == 0 ? .off : count == project.folders.count ? .on : .mixed
    }

    func toggle(_ project: ProjectJunk) {
        let ids = project.folders.map(\.id)
        if state(of: project) == .on { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    func toggle(_ folder: ProjectFolder) {
        if selection.contains(folder.id) { selection.remove(folder.id) } else { selection.insert(folder.id) }
    }

    /// Ticks every folder of every project shown under the current age filter.
    func selectVisible() {
        withAnimation(.snappy) { selection = Set(visible.flatMap { $0.folders.map(\.id) }) }
    }

    func ignore(_ project: ProjectJunk) {
        Prefs.ignore([project.project])
        withAnimation(.snappy) {
            projects.removeAll { $0.id == project.id }
            selection.subtract(project.folders.map(\.id))
        }
    }

    func remove(toTrash: Bool) {
        let targets = Dictionary(uniqueKeysWithValues: allFolders.filter { selection.contains($0.id) }.map { ($0.url, $0.footprint.size) })
        Task {
            let result = await Cleaner.remove(targets, toTrash: toTrash, source: "Projects")
            withAnimation(.snappy) {
                report = result
                projects = projects.compactMap { project in
                    let left = project.folders.filter { FileManager.default.fileExists(atPath: $0.url.path) }
                    return left.isEmpty ? nil : ProjectJunk(project: project.project, folders: left)
                }
                selection = selection.filter { id in allFolders.contains { $0.id == id } }
            }
        }
    }

    func emptyTrash() {
        Task { _ = await Cleaner.emptyTrash(); report?.movedToTrash = false }
    }
}
