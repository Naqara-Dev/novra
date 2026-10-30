import Foundation

/// Thread-safe list for results gathered in parallel.
final class Collector<T>: @unchecked Sendable {
    private var storage: [T] = []
    private let lock = NSLock()
    func append(_ item: T) { lock.withLock { storage.append(item) } }
    var items: [T] { lock.withLock { storage } }
}

final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int { lock.withLock { value += 1; return value } }
}

/// Runs heavy work off the main actor, and cancels it when the calling task is cancelled.
func runDetached<T: Sendable>(priority: TaskPriority = .userInitiated, _ body: @escaping @Sendable () -> T) async -> T {
    let work = Task.detached(priority: priority) { body() }
    return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
}
