import Foundation

/// Runs command-line tools off the main thread.
enum Shell {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var ok: Bool { status == 0 }
    }

    static let searchPath = "/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func run(_ executable: String, _ arguments: [String] = []) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ["PATH": searchPath, "HOME": Cleaner.home.path]
            do { try process.run() } catch { return Result(status: -1, output: error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }

    /// Like `run`, but hands over each line of output as it's printed.
    static func stream(_ executable: String, _ arguments: [String] = [],
                       onLine: @escaping @Sendable (String) -> Void) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ["PATH": searchPath, "HOME": Cleaner.home.path]
            let lines = LineBuffer(onLine: onLine)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { lines.feed(data) }
            }
            do { try process.run() } catch { return Result(status: -1, output: error.localizedDescription) }
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            lines.feed(pipe.fileHandleForReading.readDataToEndOfFile())
            lines.flush()
            return Result(status: process.terminationStatus, output: lines.all.joined(separator: "\n"))
        }.value
    }

    /// Runs a shell command as administrator. macOS shows its own password prompt.
    static func runAsAdmin(_ command: String) async -> Result {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return await run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }

    /// Adds up sizes like "1.751GB" or "120.5 MB" on lines containing `marker`.
    static func parseSizes(_ text: String, marker: String) -> Int64 {
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("kB", 1e3),
                                         ("GiB", 1_073_741_824), ("MiB", 1_048_576), ("KiB", 1024), ("B", 1)]
        var total = 0.0
        for line in text.split(separator: "\n") where line.lowercased().contains(marker.lowercased()) {
            let compact = line.replacingOccurrences(of: " ", with: "")
            for (unit, factor) in units {
                if let range = compact.range(of: "([0-9]+(\\.[0-9]+)?)\(unit)", options: .regularExpression) {
                    let number = compact[range].dropLast(unit.count)
                    total += (Double(number) ?? 0) * factor
                    break
                }
            }
        }
        return Int64(total)
    }

    /// First existing path among candidates, for tools that live in different places.
    static func find(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Splits streamed output into lines, from whichever thread the pipe reports on.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private(set) var all: [String] = []
    private let lock = NSLock()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        let ready: [String] = lock.withLock {
            pending.append(data)
            var out: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                out.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
            all += out
            return out
        }
        ready.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.forEach(onLine)
    }

    func flush() {
        let rest: String? = lock.withLock {
            guard !pending.isEmpty else { return nil }
            defer { pending = Data() }
            let line = String(decoding: pending, as: UTF8.self)
            all.append(line)
            return line
        }
        if let rest, !rest.trimmingCharacters(in: .whitespaces).isEmpty { onLine(rest) }
    }
}
