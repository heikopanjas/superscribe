import Foundation

/// Coalesces loads while allowing each waiter to cancel independently.
public actor LoadOnce<Value: Sendable> {
    private var cached: Value?
    private var loadingTask: Task<Void, Never>?
    private var generation: UUID?
    private var waiters: [UUID: CheckedContinuation<Value, any Error>] = [:]

    public init() {}

    public func get(_ load: @Sendable @escaping () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if let cached = self.cached { return cached }
        let id = UUID()
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                SuperscribeKitTestHooks.loadWaiterWillRegister?()
                if Task.isCancelled == true {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.waiters[id] = continuation
                if self.loadingTask == nil {
                    let generation = UUID()
                    self.generation = generation
                    self.loadingTask = Task {
                        let result: Result<Value, any Error>
                        do { result = .success(try await load()) }
                        catch { result = .failure(error) }
                        self.finish(result, generation: generation)
                    }
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) -> Void {
        if let waiter = self.waiters.removeValue(forKey: id) {
            waiter.resume(throwing: CancellationError())
            if self.waiters.isEmpty == true {
                self.loadingTask?.cancel()
                self.loadingTask = nil
                self.generation = nil
            }
        }
    }

    private func finish(_ result: Result<Value, any Error>, generation: UUID) -> Void {
        guard self.generation == generation else { return }
        self.loadingTask = nil
        self.generation = nil
        if case .success(let value) = result { self.cached = value }
        let waiters = self.waiters.values
        self.waiters.removeAll()
        for waiter in waiters { waiter.resume(with: result) }
    }
}
