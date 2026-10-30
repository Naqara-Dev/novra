import AppKit
import Photos
import Vision
import ImageIO
import QuickLookThumbnailing

struct PhotoItem: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case asset(String)
        case file(URL)
    }

    let id: String
    let source: Source
    let name: String
    let date: Date?
    let size: Int64
    let pixels: Int
    let isVideo: Bool
    let duration: Double
    let isScreenshot: Bool
    var sharpness: Double = 0
    var brightness: Double = 0
    var width = 0
    var height = 0

    var fileURL: URL? { if case .file(let url) = source { url } else { nil } }
    var assetID: String? { if case .asset(let id) = source { id } else { nil } }
}

struct PhotoReport: Sendable {
    /// Each group is sorted best first.
    var similar: [[PhotoItem]] = []
    var blurry: [PhotoItem] = []
    var dark: [PhotoItem] = []
    var screenshots: [PhotoItem] = []
    var videos: [PhotoItem] = []
    var scanned = 0
}

/// Finds similar, blurry, dark photos, screenshots and big videos. Everything runs on this Mac.
enum PhotoAnalyzer {
    typealias Progress = @Sendable (_ phase: String, _ fraction: Double) -> Void

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "dng"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    // MARK: Gathering

    static func gatherLibrary() -> [PhotoItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: options)
        var items: [PhotoItem] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image || asset.mediaType == .video else { return }
            let resource = PHAssetResource.assetResources(for: asset).first
            let size = (resource?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
            items.append(PhotoItem(id: asset.localIdentifier, source: .asset(asset.localIdentifier),
                                   name: resource?.originalFilename ?? "Photo", date: asset.creationDate, size: size,
                                   pixels: asset.pixelWidth * asset.pixelHeight, isVideo: asset.mediaType == .video,
                                   duration: asset.duration, isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot)))
        }
        return items
    }

    static func gatherFolders(_ folders: [URL]) -> [PhotoItem] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .isRegularFileKey]
        let screenshotPrefixes = ["screenshot", "screen shot", "cuplikan layar", "tangkapan layar", "capture d"]
        var items: [PhotoItem] = []
        for folder in folders {
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let url = walker.nextObject() as? URL {
                let ext = url.pathExtension.lowercased()
                let isVideo = videoExtensions.contains(ext)
                guard isVideo || imageExtensions.contains(ext),
                      let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      !FileSizer.isDataless(url) else { continue }
                let name = url.lastPathComponent
                let lower = name.lowercased()
                items.append(PhotoItem(id: url.path, source: .file(url), name: name, date: v.creationDate,
                                       size: Int64(v.fileSize ?? 0), pixels: 0, isVideo: isVideo, duration: 0,
                                       isScreenshot: screenshotPrefixes.contains { lower.hasPrefix($0) }))
            }
        }
        return items.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    // MARK: Thumbnails

    static func thumbnail(for item: PhotoItem, maxPixel: Int) -> CGImage? {
        switch item.source {
        case .asset(let id):
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            var result: CGImage?
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: maxPixel, height: maxPixel),
                                                  contentMode: .aspectFit, options: options) { image, _ in
                result = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            return result
        case .file(let url):
            if item.isVideo { return quickLookThumbnail(url, maxPixel: maxPixel) }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
    }

    static func quickLookThumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: maxPixel, height: maxPixel),
                                                   scale: 1, representationTypes: .thumbnail)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var image: CGImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            image = rep?.cgImage
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        return image
    }

    // MARK: Analysis

    /// Sharpness is the variance of the Laplacian; brightness is mean luminance (0–255).
    static func measure(_ image: CGImage) -> (sharpness: Double, brightness: Double) {
        let side = 256
        let scale = Double(side) / Double(max(image.width, image.height))
        let w = max(Int(Double(image.width) * scale), 8), h = max(Int(Double(image.height) * scale), 8)
        var pixels = [UInt8](repeating: 0, count: w * h)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return (0, 0) }
        var sum = 0.0, lapSum = 0.0, lapSq = 0.0
        for p in pixels { sum += Double(p) }
        var count = 0.0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let lap = 4 * Double(pixels[i]) - Double(pixels[i - 1]) - Double(pixels[i + 1]) - Double(pixels[i - w]) - Double(pixels[i + w])
                lapSum += lap
                lapSq += lap * lap
                count += 1
            }
        }
        let mean = lapSum / count
        return (lapSq / count - mean * mean, sum / Double(w * h))
    }

    static func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results?.first
    }

    static func analyze(_ all: [PhotoItem], progress: Progress) -> PhotoReport {
        var report = PhotoReport()
        report.videos = all.filter { $0.isVideo && $0.size >= 50_000_000 }.sorted { $0.size > $1.size }
        let images = all.filter { !$0.isVideo }
        report.scanned = images.count

        let measured = SlotArray<PhotoItem>(count: images.count)
        let prints = SlotArray<FeaturePrintBox>(count: images.count)
        let done = Counter()
        DispatchQueue.concurrentPerform(iterations: images.count) { index in
            guard !Task.isCancelled else { return }
            var item = images[index]
            if let url = item.fileURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                item.width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                item.height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            }
            if let thumb = thumbnail(for: item, maxPixel: 360) {
                let (sharpness, brightness) = measure(thumb)
                item.sharpness = sharpness
                item.brightness = brightness
                if let print = featurePrint(thumb) { prints.set(index, FeaturePrintBox(print)) }
            }
            measured.set(index, item)
            let n = done.increment()
            if n % 10 == 0 { progress("Looking at your photos", Double(n) / Double(max(images.count, 1))) }
        }
        guard !Task.isCancelled else { return report }
        let analyzed = (0..<images.count).map { measured.get($0) ?? images[$0] }

        // Similar: compare each photo with the few taken just before it.
        var parent = Array(0..<analyzed.count)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in analyzed.indices {
            guard let a = prints.get(i) else { continue }
            for j in max(0, i - 6)..<i {
                guard let b = prints.get(j) else { continue }
                if let ta = analyzed[i].date, let tb = analyzed[j].date, abs(ta.timeIntervalSince(tb)) > 6 * 3600 { continue }
                var distance: Float = 1
                try? a.value.computeDistance(&distance, to: b.value)
                if distance < 0.4 { parent[root(i)] = root(j) }
            }
        }
        let groups = Dictionary(grouping: analyzed.indices, by: root).values.filter { $0.count > 1 }
        report.similar = groups.map { indices in
            indices.map { analyzed[$0] }.sorted { score($0) > score($1) }
        }
        .sorted { $0.dropFirst().map(\.size).sum > $1.dropFirst().map(\.size).sum }

        let inGroups = Set(report.similar.flatMap { $0.map(\.id) })
        report.screenshots = analyzed.filter(\.isScreenshot)
        // Blur and darkness only make sense for camera photos, not icons, logos or UI graphics.
        let photos = analyzed.filter(isCameraPhoto)
        report.dark = photos.filter { $0.brightness > 0 && $0.brightness < 30 }
        report.blurry = photos.filter {
            !inGroups.contains($0.id) && $0.brightness >= 30 && $0.sharpness > 0 && $0.sharpness < 45
        }
        return report
    }

    private static let cameraExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "dng", "tif", "tiff"]

    static func isCameraPhoto(_ item: PhotoItem) -> Bool {
        guard !item.isScreenshot, !item.isVideo else { return false }
        if item.assetID != nil { return true }
        guard let url = item.fileURL, cameraExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return item.width * item.height >= 300_000
    }

    /// Prefers sharp, large, well-exposed shots.
    static func score(_ item: PhotoItem) -> Double {
        item.sharpness * log(Double(max(item.pixels, item.width * item.height, 1)) + 10) * (item.brightness < 30 ? 0.5 : 1)
    }
}

/// Vision observations aren't Sendable; this box lets them sit in a shared slot array.
final class FeaturePrintBox: @unchecked Sendable {
    let value: VNFeaturePrintObservation
    init(_ value: VNFeaturePrintObservation) { self.value = value }
}

final class SlotArray<T>: @unchecked Sendable {
    private var slots: [T?]
    private let lock = NSLock()
    init(count: Int) { slots = Array(repeating: nil, count: count) }
    func set(_ index: Int, _ value: T) { lock.withLock { slots[index] = value } }
    func get(_ index: Int) -> T? { lock.withLock { slots[index] } }
}
