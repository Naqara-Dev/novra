import Foundation
import UserNotifications

/// Warns when the disk runs low, while Novra is running. Nothing is scheduled in the background.
@MainActor
final class LowDiskWatcher {
    static let shared = LowDiskWatcher()
    private var task: Task<Void, Never>?
    private var lastAlert: Date = .distantPast

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                check()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    private func check() {
        guard UserDefaults.standard.bool(forKey: Prefs.Key.lowDiskAlert) else { return }
        let disk = SystemInfo.disk()
        let limit = Int64(Prefs.lowDiskGB) * 1_000_000_000
        guard disk.free < limit, Date.now.timeIntervalSince(lastAlert) > 6 * 3600 else { return }
        lastAlert = .now
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your Mac is almost full")
        content.body = String(localized: "Only \(disk.free.byteString) left. Open Novra to see what's safe to clear.")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lowdisk", content: content, trigger: nil))
    }
}
