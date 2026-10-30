import SwiftUI
import Photos

@MainActor @Observable
final class PhotosModel {
    enum Source: String, CaseIterable { case library = "Photos Library", folders = "Folders" }
    enum Section: String, CaseIterable, Identifiable {
        case similar = "Similar", blurry = "Blurry", dark = "Dark", screenshots = "Screenshots", videos = "Large Videos"
        var id: String { rawValue }
    }

    var source: Source = .library
    var report = PhotoReport()
    var isScanning = false
    var hasScanned = false
    var progress: Double = 0
    var phase = ""
    var selection: Set<String> = []
    var denied = false
    var message: String?
    var swipe: [PhotoItem]?
    private var task: Task<Void, Never>?

    let folders = ["Pictures", "Desktop", "Downloads", "Documents"].map { Cleaner.home.appending(path: $0) }

    func items(in section: Section) -> [PhotoItem] {
        switch section {
        case .similar: report.similar.flatMap { $0 }
        case .blurry: report.blurry
        case .dark: report.dark
        case .screenshots: report.screenshots
        case .videos: report.videos
        }
    }

    var allItems: [PhotoItem] {
        var seen = Set<String>()
        return Section.allCases.flatMap { items(in: $0) }.filter { seen.insert($0.id).inserted }
    }

    var selectedItems: [PhotoItem] { allItems.filter { selection.contains($0.id) } }
    var selectionSize: Int64 { selectedItems.map(\.size).sum }

    func scan() {
        task?.cancel()
        message = nil
        task = Task {
            if source == .library {
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                guard status == .authorized || status == .limited else {
                    denied = true
                    return
                }
            }
            denied = false
            isScanning = true
            hasScanned = true
            progress = 0
            phase = String(localized: "Gathering photos")
            selection = []
            let source = self.source, folders = self.folders
            let result = await Task.detached(priority: .userInitiated) { [self] in
                let items = source == .library ? PhotoAnalyzer.gatherLibrary() : PhotoAnalyzer.gatherFolders(folders)
                return PhotoAnalyzer.analyze(items) { phase, fraction in
                    Task { @MainActor in
                        self.phase = String(localized: String.LocalizationValue(phase))
                        self.progress = fraction
                    }
                }
            }.value
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                report = result
                // Keep the best shot of each group; offer the rest.
                selection = Set(result.similar.flatMap { $0.dropFirst().map(\.id) })
                isScanning = false
            }
        }
    }

    func toggle(_ item: PhotoItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func selectAll(_ section: Section) {
        let ids = section == .similar ? report.similar.flatMap { $0.dropFirst().map(\.id) } : items(in: section).map(\.id)
        withAnimation(.snappy) {
            if ids.allSatisfy(selection.contains) { selection.subtract(ids) } else { selection.formUnion(ids) }
        }
    }

    func startSwipe(_ section: Section) {
        let list = section == .similar ? report.similar.flatMap { $0.dropFirst() } : items(in: section)
        guard !list.isEmpty else { return }
        swipe = list
    }

    func finishSwipe(delete: [PhotoItem]) {
        swipe = nil
        guard !delete.isEmpty else { return }
        selection = Set(delete.map(\.id))
        remove()
    }

    /// Library photos go to Recently Deleted (macOS asks first); files go to the Trash.
    func remove() {
        let chosen = selectedItems
        Task {
            var report = CleanReport(movedToTrash: true)
            let assets = chosen.compactMap(\.assetID)
            if !assets.isEmpty {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assets, options: nil)
                        PHAssetChangeRequest.deleteAssets(fetched)
                    }
                    let removed = chosen.filter { $0.assetID != nil }
                    report.removed += removed.count
                    report.freed += removed.map(\.size).sum
                    report.items += removed.map { CleanRecord.Item(original: "Photos › \($0.name)", trashed: nil, size: $0.size) }
                    History.shared.add(source: "Photos", report: report)
                    message = String(localized: "Moved \(removed.count) photos to Recently Deleted in Photos. They stay there for 30 days.")
                } catch {
                    message = String(localized: "Nothing was deleted.")
                }
            }
            let files = Dictionary(chosen.compactMap { item in item.fileURL.map { ($0, item.size) } }, uniquingKeysWith: { a, _ in a })
            if !files.isEmpty {
                _ = await Cleaner.remove(files, toTrash: Prefs.defaultToTrash, source: "Photos")
            }
            let gone = Set(chosen.filter { item in
                if let url = item.fileURL { return !FileManager.default.fileExists(atPath: url.path) }
                return PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).count == 0
            }.map(\.id))
            withAnimation(.snappy) { drop(gone) }
        }
    }

    func drop(_ ids: Set<String>) {
        report.similar = report.similar.map { $0.filter { !ids.contains($0.id) } }.filter { $0.count > 1 }
        report.blurry.removeAll { ids.contains($0.id) }
        report.dark.removeAll { ids.contains($0.id) }
        report.screenshots.removeAll { ids.contains($0.id) }
        report.videos.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func replace(_ old: PhotoItem, withSize size: Int64) {
        report.videos = report.videos.map { $0.id == old.id ? PhotoItem(id: $0.id, source: $0.source, name: $0.name, date: $0.date,
                                                                          size: size, pixels: $0.pixels, isVideo: true,
                                                                          duration: $0.duration, isScreenshot: false) : $0 }
    }
}
