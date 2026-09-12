import Foundation

/// A synchronous barrier for callbacks on owned blocking workers.
final class BlockingTestGate: @unchecked Sendable {
    private let lock = NSLock()
    private let permits = DispatchSemaphore(value: 0)
    private var active = 0
    private var maximum = 0
    private var arrivals = 0
    let initialBatch = TestSignal()
    let nextArrival = TestSignal()

    var peak: Int { return self.lock.withLock { self.maximum } }
    var current: Int { return self.lock.withLock { self.active } }

    func enter() -> Void {
        self.lock.withLock {
            self.active += 1
            self.arrivals += 1
            self.maximum = max(self.maximum, self.active)
            if self.arrivals == 2 { self.initialBatch.signal() }
            if self.arrivals == 3 { self.nextArrival.signal() }
        }
        self.permits.wait()
        self.lock.withLock { self.active -= 1 }
    }

    func release() -> Void { self.permits.signal() }
}
