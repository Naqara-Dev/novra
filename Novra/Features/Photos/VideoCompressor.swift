import AVFoundation
import Photos

/// Re-encodes a video as HEVC 1080p. Keeps the original in the Trash (files) or Recently Deleted (Photos).
@MainActor @Observable
final class VideoCompressor {
    static let shared = VideoCompressor()

    var progress: [String: Double] = [:]
    var results: [String: String] = [:]

    func isBusy(_ id: String) -> Bool { progress[id] != nil }

    func compress(_ item: PhotoItem, onDone: @escaping (Int64) -> Void) {
        guard progress[item.id] == nil else { return }
        progress[item.id] = 0
        results[item.id] = nil
        Task {
            do {
                let saved = try await run(item)
                results[item.id] = saved > 0 ? String(localized: "Saved \(saved.byteString)") : String(localized: "Already compact")
                onDone(max(item.size - saved, 0))
            } catch {
                results[item.id] = String(localized: "Couldn't compress")
            }
            progress[item.id] = nil
        }
    }

    private func run(_ item: PhotoItem) async throws -> Int64 {
        let input: AVAsset
        var original: PHAsset?
        if let url = item.fileURL {
            input = AVURLAsset(url: url)
        } else if let id = item.assetID, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
            original = asset
            let box: AssetBox = try await withCheckedThrowingContinuation { continuation in
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = false
                options.deliveryMode = .highQualityFormat
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                    if let avAsset { continuation.resume(returning: AssetBox(avAsset)) } else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
                }
            }
            input = box.asset
        } else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard let session = AVAssetExportSession(asset: input, presetName: AVAssetExportPresetHEVC1920x1080) else {
            throw CocoaError(.featureUnsupported)
        }
        let output = FileManager.default.temporaryDirectory.appending(path: "novra-\(UUID().uuidString).mov")
        session.outputURL = output
        session.outputFileType = .mov
        let id = item.id
        let poll = Task { [weak session] in
            while !Task.isCancelled, let session {
                self.progress[id] = Double(session.progress)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        await session.export()
        poll.cancel()
        guard session.status == .completed else { throw session.error ?? CocoaError(.fileWriteUnknown) }

        let newSize = Int64((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        // Only worth it if it saves at least 10%.
        guard newSize > 0, newSize < item.size * 9 / 10 else {
            try? FileManager.default.removeItem(at: output)
            return 0
        }

        if let url = item.fileURL {
            let target = url.deletingPathExtension().appendingPathExtension("compressed.mov")
            try FileManager.default.moveItem(at: output, to: target)
            var landed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            let report = CleanReport(freed: item.size - newSize, removed: 1, movedToTrash: true,
                                     items: [CleanRecord.Item(original: url.path, trashed: landed?.path, size: item.size)])
            History.shared.add(source: "Compress Video", report: report)
        } else if let original {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: output, options: nil)
                request.creationDate = original.creationDate
                request.location = original.location
                PHAssetChangeRequest.deleteAssets([original] as NSArray)
            }
            try? FileManager.default.removeItem(at: output)
        }
        return item.size - newSize
    }
}

/// Photos hands the asset over on its own queue; it's only read afterwards.
private final class AssetBox: @unchecked Sendable {
    let asset: AVAsset
    init(_ asset: AVAsset) { self.asset = asset }
}
