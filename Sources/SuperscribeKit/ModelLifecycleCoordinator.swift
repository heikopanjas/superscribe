import Foundation

/// Cancellation-aware FIFO admission for model installation and removal.
internal actor ModelLifecycleCoordinator {
    internal static let shared = ModelLifecycleCoordinator()

    private struct Waiter {
        var previous: UUID?
        var next: UUID?
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var held = false
    private var head: UUID?
    private var tail: UUID?
    private var waiters: [UUID: Waiter] = [:]
    private let onQueued: @Sendable () -> Void

    internal init(onQueued: @Sendable @escaping () -> Void = {}) {
        self.onQueued = onQueued
    }

    internal func withLock<Value: Sendable>(body: @Sendable @escaping () async throws -> Value) async throws -> Value {
        try await self.acquire()
        defer { self.release() }
        try Task.checkCancellation()
        return try await body()
    }

    private func acquire() async throws -> Void {
        try Task.checkCancellation()
        if self.held == false {
            self.held = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.onQueued()
                if Task.isCancelled == true {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.waiters[id] = Waiter(previous: self.tail, next: nil, continuation: continuation)
                if let tail = self.tail {
                    self.waiters[tail]?.next = id
                }
                else {
                    self.head = id
                }
                self.tail = id
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func remove(_ id: UUID) -> Waiter? {
        guard let waiter = self.waiters.removeValue(forKey: id) else { return nil }
        if let previous = waiter.previous {
            self.waiters[previous]?.next = waiter.next
        }
        else {
            self.head = waiter.next
        }
        if let next = waiter.next {
            self.waiters[next]?.previous = waiter.previous
        }
        else {
            self.tail = waiter.previous
        }
        return waiter
    }

    private func cancel(_ id: UUID) -> Void {
        self.remove(id)?.continuation.resume(throwing: CancellationError())
    }

    private func release() -> Void {
        if let head = self.head {
            self.remove(head)?.continuation.resume()
        }
        else {
            self.held = false
        }
    }
}
