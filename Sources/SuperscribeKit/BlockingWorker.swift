import Foundation

/// Owns a serial queue for blocking framework and filesystem operations.
/// Queue identity is immutable after initialization; all submitted work is serialized.
internal final class BlockingWorker: @unchecked Sendable {
    private let queue: DispatchQueue
    private let identity = DispatchSpecificKey<Bool>()

    internal init(label: String) {
        self.queue = DispatchQueue(label: label)
        self.queue.setSpecific(key: self.identity, value: true)
    }

    internal func run<Value: Sendable>(_ operation: @Sendable @escaping (CancellationFlag) throws -> Value) async throws -> Value {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                self.queue.async {
                    do {
                        try cancellation.check()
                        let value = try operation(cancellation)
                        try cancellation.check()
                        continuation.resume(returning: value)
                    }
                    catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// Runs lifetime cleanup on the owner queue, including when released there.
    internal func sync<Value>(_ operation: () throws -> Value) rethrows -> Value {
        if DispatchQueue.getSpecific(key: self.identity) == true {
            return try operation()
        }
        return try self.queue.sync(execute: operation)
    }
}
