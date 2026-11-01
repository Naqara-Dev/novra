import SwiftUI

/// A record of every clean, kept on this Mac only, so people can see what went and bring it back.
struct CleanRecord: Codable, Identifiable, Sendable {
    struct Item: Codable, Hashable, Sendable {
        let original: String
        /// Where the item sits in the Trash, when it was moved there.
        let trashed: String?
        let size: Int64
    }

    var id = UUID()
    let date: Date
    let source: String
    let freed: Int64
    let movedToTrash: Bool
    var items: [Item]
    var restored = false

    var restorable: [Item] {
        items.filter { item in item.trashed.map { FileManager.default.fileExists(atPath: $0) } ?? false }
    }
}

@MainActor @Observable
final class History {
    static let shared = History()

    private(set) var records: [CleanRecord] = []
    private let saveQueue = DispatchQueue(label: "com.naqara.novra.history-save", qos: .utility)
    private let file: URL = {
        // Tests point this elsewhere so they never touch the real history.
        if let custom = ProcessInfo.processInfo.environment["NOVRA_HISTORY_PATH"] { return URL(filePath: custom) }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Novra", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "history.json")
    }()

    init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([CleanRecord].self, from: data) {
            records = saved
        }
    }

    var totalFreed: Int64 { records.filter { !$0.restored }.map(\.freed).sum }

    func add(source: String, report: CleanReport) {
        guard report.removed > 0 else { return }
        let record = CleanRecord(date: .now, source: source, freed: report.freed, movedToTrash: report.movedToTrash,
                                 items: Array(report.items.prefix(2_000)))
        withAnimation(.snappy) { records.insert(record, at: 0) }
        records = Array(records.prefix(300))
        save()
    }

    /// Moves everything still in the Trash back where it came from.
    func restore(_ record: CleanRecord) -> (restored: Int, failed: Int) {
        var restored = 0, failed = 0
        let fm = FileManager.default
        for item in record.restorable {
            guard let trashed = item.trashed else { continue }
            let target = URL(filePath: item.original)
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: target.path), (try? fm.moveItem(atPath: trashed, toPath: target.path)) != nil {
                restored += 1
            } else {
                failed += 1
            }
        }
        if let index = records.firstIndex(where: { $0.id == record.id }), record.restorable.isEmpty || restored > 0 {
            records[index].restored = records[index].restorable.isEmpty
        }
        save()
        return (restored, failed)
    }

    func forget(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clear() {
        records = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        let target = file
        saveQueue.async { try? data.write(to: target, options: .atomic) }
    }

    func waitForPendingSaves() { saveQueue.sync {} }
}
