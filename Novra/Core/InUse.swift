import Foundation

/// Which of this user's files are open right now, and by what. Used to leave alone
/// anything a running program still holds, such as a build cache gopls is writing to.
struct OpenFiles: Sendable {
    /// Open paths, sorted, each mapped to the name of a process holding it.
    private let paths: [String]
    private let holders: [String]

    static let empty = OpenFiles(paths: [], holders: [])

    private init(paths: [String], holders: [String]) {
        self.paths = paths
        self.holders = holders
    }

    /// One `lsof` pass over this user's processes. Takes a second or two on a busy Mac.
    static func snapshot() async -> OpenFiles {
        let result = await Shell.run("/usr/sbin/lsof", ["-nP", "-w", "+c", "0", "-u", String(getuid()), "-Fcn"])
        guard !result.output.isEmpty else { return .empty }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var pairs: [(String, String)] = []
        var command = ""
        var skip = false
        // Your files, and apps in /Applications (a running app keeps its own frameworks open).
        let roots = [Cleaner.home.path + "/", "/Applications/"]
        for line in result.output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": skip = Int32(value) == ownPID
            case "c": command = value
            case "n" where !skip && roots.contains(where: value.hasPrefix): pairs.append((value, command))
            default: break
            }
        }
        pairs.sort { $0.0 < $1.0 }
        return OpenFiles(paths: pairs.map(\.0), holders: pairs.map(\.1))
    }

    /// The process holding `url` or anything inside it, if one does.
    func holder(of url: URL) -> String? {
        let path = url.standardizedFileURL.path
        // First open path that is >= `path`; anything inside the folder sorts right after it.
        var low = 0, high = paths.count
        while low < high {
            let mid = (low + high) / 2
            if paths[mid] < path { low = mid + 1 } else { high = mid }
        }
        var index = low
        while index < paths.count {
            let candidate = paths[index]
            if candidate == path || candidate.hasPrefix(path + "/") { return holders[index] }
            if !candidate.hasPrefix(path) { break }
            index += 1
        }
        return nil
    }

    func holder(ofAny urls: [URL]) -> String? {
        for url in urls { if let name = holder(of: url) { return name } }
        return nil
    }
}

/// A short-lived shared snapshot, so a scan of twelve categories runs `lsof` once.
actor OpenFilesCache {
    static let shared = OpenFilesCache()
    private var cached: (OpenFiles, Date)?

    func current(maxAge: TimeInterval = 30) async -> OpenFiles {
        if let (files, taken) = cached, Date().timeIntervalSince(taken) < maxAge { return files }
        let files = await OpenFiles.snapshot()
        cached = (files, Date())
        return files
    }
}
