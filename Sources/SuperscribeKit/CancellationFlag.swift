import Foundation

/// Synchronous cancellation bridge for blocking APIs and C callbacks.
internal final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    internal var isCancelled: Bool {
        return self.lock.withLock { return self.cancelled }
    }

    internal func cancel() -> Void {
        self.lock.withLock { self.cancelled = true }
    }

    internal func check() throws -> Void {
        if self.isCancelled == true { throw CancellationError() }
    }
}
