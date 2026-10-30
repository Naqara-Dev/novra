import SwiftUI
import CryptoKit

struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let files: [DupFile]
    var wasted: Int64 { files.dropFirst().map(\.size).sum }
}

struct DupFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let created: Date?
}

enum DuplicateFinder {
    typealias Progress = @Sendable (_ path: String, _ fraction: Double) -> Void

    /// Groups files with identical content. Size first, then a quick hash of both ends, then the full hash.
    static func find(in folders: [URL], minSize: Int64, progress: Progress) -> [DuplicateGroup] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .isSymbolicLinkKey]
        var bySize: [Int64: [DupFile]] = [:]
        var seen = Set<String>()
        let ignored = Prefs.ignored
        for folder in folders {
            guard let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
            ) else { continue }
            var visited = 0
            for case let url as URL in walker {
                visited += 1
                if visited % 500 == 0 {
                    if Task.isCancelled { return [] }
                    progress(url.path, 0.1)
                }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      v.isSymbolicLink != true, let size = v.fileSize, Int64(size) >= minSize,
                      !Prefs.isIgnored(url, in: ignored), !FileSizer.isDataless(url),
                      seen.insert(url.standardizedFileURL.path).inserted else { continue }
                bySize[Int64(size), default: []].append(DupFile(url: url, size: Int64(size), created: v.creationDate))
            }
        }

        let candidates = bySize.values.filter { $0.count > 1 }
        var groups: [DuplicateGroup] = []
        for (index, sameSize) in candidates.enumerated() {
            if Task.isCancelled { return [] }
            progress(sameSize[0].url.path, 0.1 + 0.9 * Double(index) / Double(max(candidates.count, 1)))
            let byQuick = Dictionary(grouping: sameSize) { quickHash($0.url) ?? UUID().uuidString }
            for quickGroup in byQuick.values where quickGroup.count > 1 {
                let byFull = Dictionary(grouping: quickGroup) { fullHash($0.url) ?? UUID().uuidString }
                for (hash, files) in byFull where files.count > 1 {
                    // Oldest first: that's the one Novra suggests keeping.
                    let sorted = files.sorted { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }
                    groups.append(DuplicateGroup(id: hash, files: sorted))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    private static func quickHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunk = 64 * 1024
        if let head = try? handle.read(upToCount: chunk) { hasher.update(data: head) }
        if let end = try? handle.seekToEnd(), end > UInt64(chunk) {
            try? handle.seek(toOffset: end - UInt64(chunk))
            if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            guard let data = try? handle.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor @Observable
final class DuplicatesModel {
    var folders: [URL] = ["Desktop", "Documents", "Downloads", "Pictures", "Movies"]
        .map { Cleaner.home.appending(path: $0) }
    var groups: [DuplicateGroup] = []
    var selection: Set<String> = []
    var isScanning = false
    var hasScanned = false
    var progress: Double = 0
    var currentPath = ""
    var report: CleanReport?
    private var task: Task<Void, Never>?

    var allFiles: [DupFile] { groups.flatMap(\.files) }
    var selectionSize: Int64 { allFiles.filter { selection.contains($0.id) }.map(\.size).sum }
    var wasted: Int64 { groups.map(\.wasted).sum }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls where !folders.contains(url) { folders.append(url) }
        }
    }

    func scan() {
        task?.cancel()
        isScanning = true
        hasScanned = true
        progress = 0
        selection = []
        let targets = folders
        task = Task {
            let found = await runDetached { [self] in
                DuplicateFinder.find(in: targets, minSize: 512 * 1024) { path, fraction in
                    Task { @MainActor in
                        self.currentPath = path
                        self.progress = fraction
                    }
                }
            }
            guard !Task.isCancelled else { return }
            groups = found
            selectAllButOriginals()
            isScanning = false
        }
    }

    func selectAllButOriginals() {
        selection = Set(groups.flatMap { $0.files.dropFirst().map(\.id) })
    }

    /// Ticks a copy, but never every copy in a group: one always stays.
    func toggle(_ file: DupFile, in group: DuplicateGroup) {
        if selection.contains(file.id) {
            selection.remove(file.id)
        } else if group.files.filter({ !selection.contains($0.id) }).count > 1 {
            selection.insert(file.id)
        } else {
            NSSound.beep()
        }
    }

    func remove(toTrash: Bool) {
        let targets = Dictionary(uniqueKeysWithValues: allFiles.filter { selection.contains($0.id) }.map { ($0.url, $0.size) })
        Task {
            report = await Cleaner.remove(targets, toTrash: toTrash, source: "Duplicates")
            groups = groups.compactMap { group in
                let left = group.files.filter { FileManager.default.fileExists(atPath: $0.url.path) }
                return left.count > 1 ? DuplicateGroup(id: group.id, files: left) : nil
            }
            selection = selection.filter { id in allFiles.contains { $0.id == id } }
        }
    }

    func emptyTrash() {
        Task { _ = await Cleaner.emptyTrash(); report?.movedToTrash = false }
    }
}
