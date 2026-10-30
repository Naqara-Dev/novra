import Foundation

/// What Novra knows for sure about a folder, beyond its dates.
struct Insight: Sendable {
    enum Tone: Sendable { case needed, safe, unused }
    let label: String
    let tone: Tone
}

/// Plain-language notes for well-known heavy folders, so people know what they're looking at.
enum PathHints {
    private static let hints: [(suffix: String, text: String)] = [
        ("Library/Android/sdk", "The Android SDK: platforms, build tools, emulator images."),
        ("Android/sdk/system-images", "Emulator system images. Remove Android versions you don't test on."),
        ("Android/sdk/platforms", "One folder per Android version you compile against."),
        ("Android/sdk/build-tools", "Old build-tools versions are rarely needed."),
        ("Android/sdk/ndk", "Native Development Kit. Only needed for C/C++ code."),
        ("Android/sdk/emulator", "The Android Emulator program."),
        ("Android/sdk/sources", "Android source code for debugging. Safe to remove."),
        (".android/avd", "Your virtual devices. Each one can take several GB."),
        (".android/cache", "Cache. Safe to clear."),
        (".gradle/caches", "Downloaded dependencies. Gradle downloads them again when needed."),
        (".gradle/wrapper/dists", "Gradle versions. Old ones are safe to remove."),
        (".gradle/daemon", "Gradle daemon logs. Safe to clear."),
        (".m2/repository", "Maven dependencies, shared by Java tools."),
        ("Developer/Xcode/DerivedData", "Build products. Xcode rebuilds them."),
        ("Developer/Xcode/Archives", "App archives. Keep the ones you may need for crash reports."),
        ("Developer/Xcode/iOS DeviceSupport", "Debug symbols per iOS version. Old ones are safe to remove."),
        ("Developer/CoreSimulator/Devices", "Simulator devices and the apps installed on them."),
        ("Developer/CoreSimulator/Caches", "Cache. Safe to clear."),
        ("Developer/CoreSimulator/Volumes", "Simulator runtimes."),
        ("Containers/com.docker.docker", "Docker's disk with all your images, containers and volumes."),
        ("Code Cache", "Cache. Safe to clear."),
        ("GPUCache", "Cache. Safe to clear."),
        ("Service Worker/CacheStorage", "Offline website data. Safe to clear."),
    ]

    /// Program folders an app runs from. Removing them breaks the app even if they look old.
    private static let needed: [(suffix: String, label: String)] = [
        ("Android/sdk/emulator", "Needed to run emulators"),
        ("Android/sdk/platform-tools", "Needed: adb lives here"),
        ("Android/sdk/cmdline-tools", "Needed by the SDK Manager"),
        ("Android/sdk/licenses", "Needed"),
    ]

    static func insight(for url: URL) -> Insight? {
        let path = url.path
        if let match = needed.first(where: { path.hasSuffix("/" + $0.suffix) }) {
            return Insight(label: String(localized: String.LocalizationValue(match.label)), tone: .needed)
        }
        if path.hasSuffix("/sources") && path.contains("/Android/sdk/") {
            return Insight(label: String(localized: "Safe to remove"), tone: .safe)
        }
        if let range = path.range(of: "/Android/sdk/system-images/") {
            return systemImageInsight(String(path[range.upperBound...]))
        }
        return nil
    }

    /// Checks a system image against the images your emulators are set up with.
    private static func systemImageInsight(_ relative: String) -> Insight? {
        let inUse = AndroidEmulators.imagesInUse()
        let users = inUse.filter { $0.image.hasPrefix(relative + "/") || $0.image == relative || relative.hasPrefix($0.image) }
        if users.isEmpty { return Insight(label: String(localized: "No emulator uses this"), tone: .unused) }
        let names = users.map(\.avd).sorted()
        let label = names.count == 1 ? String(localized: "Used by \(names[0])") : String(localized: "Used by \(names.count) emulators")
        return Insight(label: label, tone: .needed)
    }

    static func hint(for url: URL) -> String? {
        let path = url.path
        if url.pathExtension == "avd" { return String(localized: "A virtual device. Remove it if you no longer use this emulator.") }
        if url.pathExtension == "xcarchive" { return String(localized: "An app archive.") }
        return hints.first { path.hasSuffix("/" + $0.suffix) }.map { String(localized: String.LocalizationValue($0.text)) }
    }
}

/// Reads ~/.android/avd to learn which system images your virtual devices run.
enum AndroidEmulators {
    struct Usage: Sendable { let avd: String; let image: String }

    nonisolated(unsafe) private static var cache: (time: Date, usages: [Usage])?
    private static let lock = NSLock()

    static func imagesInUse() -> [Usage] {
        lock.withLock {
            if let cache, Date.now.timeIntervalSince(cache.time) < 5 { return cache.usages }
            let usages = readConfigs()
            cache = (.now, usages)
            return usages
        }
    }

    private static func readConfigs() -> [Usage] {
        let avdRoot = Cleaner.home.appending(path: ".android/avd")
        return FileSizer.children(of: avdRoot).filter { $0.pathExtension == "avd" }.compactMap { avd in
            guard let config = try? String(contentsOf: avd.appending(path: "config.ini"), encoding: .utf8) else { return nil }
            for line in config.split(whereSeparator: \.isNewline) where line.hasPrefix("image.sysdir.1") {
                guard let value = line.split(separator: "=", maxSplits: 1).last else { continue }
                var image = value.trimmingCharacters(in: .whitespaces)
                if image.hasPrefix("system-images/") { image.removeFirst("system-images/".count) }
                while image.hasSuffix("/") { image.removeLast() }
                return Usage(avd: avd.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " "), image: image)
            }
            return nil
        }
    }
}
