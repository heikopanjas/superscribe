import Foundation

/// A latched event for deterministic tests, including synchronous callbacks.
final class TestSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() -> Void {
        let pending = self.lock.withLock {
            self.signalled = true
            let pending = self.waiters
            self.waiters.removeAll()
            return pending
        }
        for waiter in pending { waiter.resume() }
    }

    func wait() async -> Void {
        await withCheckedContinuation { continuation in
            let resume = self.lock.withLock {
                if self.signalled == true { return true }
                self.waiters.append(continuation)
                return false
            }
            if resume == true { continuation.resume() }
        }
    }
}
