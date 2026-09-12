/// A reusable barrier that holds the first batch until every slot is occupied.
/// Later entries pass through; callers must await `leave` before returning.
actor ConcurrentTestGate {
    private let batchSize: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var current = 0
    private(set) var peak = 0

    init(batchSize: Int) {
        self.batchSize = batchSize
    }

    func enter() async -> Void {
        self.current += 1
        self.peak = max(self.peak, self.current)
        self.arrivals += 1
        if self.arrivals < self.batchSize {
            await withCheckedContinuation { continuation in
                self.waiters.append(continuation)
            }
        }
        else {
            let pending = self.waiters
            self.waiters.removeAll()
            for waiter in pending {
                waiter.resume()
            }
        }
    }

    func leave() -> Void {
        self.current -= 1
        return
    }
}
