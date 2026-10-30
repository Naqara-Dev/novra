import SwiftUI
import UniformTypeIdentifiers

struct LargeFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    /// Last opened or changed.
    let modified: Date?
    let kind: Kind

    enum Kind: String, CaseIterable, Sendable {
        case all = "All", video = "Videos", archive = "Archives", diskImage = "Disk Images", document = "Documents", other = "Other"

        static func of(_ url: URL) -> Kind {
            let ext = url.pathExtension.lowercased()
            if ["dmg", "iso", "img", "sparseimage", "sparsebundle", "pkg", "xip", "vdi", "vmdk", "qcow2"].contains(ext) { return .diskImage }
            guard let type = UTType(filenameExtension: ext) else { return .other }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .archive) || ["zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext) { return .archive }
            if type.conforms(to: .pdf) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet)
                || type.conforms(to: .text) || type.conforms(to: .image) || type.conforms(to: .audio) { return .document }
            return .other
        }
    }
}

enum LargeFileScanner {
    typealias Progress = @Sendable (String) -> Void

    static func scan(minSize: Int64, progress: Progress) -> [LargeFile] {
        let home = Cleaner.home
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .contentAccessDateKey]
        // ~/Library belongs to apps (see Apps); hidden folders hold tool data that breaks if pulled apart.
        guard let walker = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [] }
        let skip: Set<String> = [home.appending(path: "Library").path, home.appending(path: ".Trash").path]
        var found: [LargeFile] = []
        var visited = 0
        let ignored = Prefs.ignored
        for case let url as URL in walker {
            visited += 1
            if visited % 500 == 0 {
                if Task.isCancelled { break }
                progress(url.path)
            }
            if skip.contains(url.path) || ignored.contains(url.path) { walker.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? 0)
            if size >= minSize {
                let used = [v.contentModificationDate, v.contentAccessDate].compactMap { $0 }.max()
                found.append(LargeFile(url: url, size: size, modified: used, kind: .of(url)))
            }
        }
        return found.sorted { $0.size > $1.size }
    }
}

@MainActor @Observable
final class LargeFilesModel {
    static let thresholds: [Int64] = [50, 100, 500, 1000].map { $0 * 1_000_000 }

    var files: [LargeFile] = []
    var isScanning = false
    var hasScanned = false
    var currentPath = ""
    var minSize: Int64 = 100_000_000 {
        didSet { if hasScanned && oldValue != minSize { scan() } }
    }
    var filter: LargeFile.Kind = .all
    var onlyOld = false
    var selection: Set<String> = []
    var report: CleanReport?
    private var task: Task<Void, Never>?

    var visible: [LargeFile] {
        files.filter { file in
            (filter == .all || file.kind == filter) && (!onlyOld || file.modified?.isStale == true)
        }
    }

    var selectionSize: Int64 { files.filter { selection.contains($0.id) }.map(\.size).sum }

    func scan() {
        task?.cancel()
        isScanning = true
        hasScanned = true
        selection = []
        let min = minSize
        task = Task {
            let found = await runDetached { [self] in
                LargeFileScanner.scan(minSize: min) { path in
                    Task { @MainActor in self.currentPath = path }
                }
            }
            guard !Task.isCancelled else { return }
            files = found
            isScanning = false
        }
    }

    func ignore(_ file: LargeFile) {
        Prefs.ignore([file.url])
        withAnimation(.snappy) {
            files.removeAll { $0.id == file.id }
            selection.remove(file.id)
        }
    }

    func toggle(_ file: LargeFile) {
        if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
    }

    func remove(toTrash: Bool) {
        let targets = Dictionary(uniqueKeysWithValues: files.filter { selection.contains($0.id) }.map { ($0.url, $0.size) })
        Task {
            let result = await Cleaner.remove(targets, toTrash: toTrash, source: "Large Files")
            withAnimation(.snappy) {
                report = result
                files.removeAll { selection.contains($0.id) && !FileManager.default.fileExists(atPath: $0.url.path) }
                selection = selection.filter { id in files.contains { $0.id == id } }
            }
        }
    }

    func emptyTrash() {
        Task { _ = await Cleaner.emptyTrash(); report?.movedToTrash = false }
    }
}
