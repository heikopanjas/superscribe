import Testing

@testable import SuperscribeKit

@Suite("Model lifecycle FIFO")
struct ModelLifecycleCoordinatorTests {
    @Test(arguments: [0, 1, 2])
    func cancelledWaitersAreRemovedWithoutBreakingFIFO(cancelIndex: Int) async throws -> Void {
        let queued = [TestSignal(), TestSignal(), TestSignal()]
        let count = TestDependencyStorage(0)
        let coordinator = ModelLifecycleCoordinator(onQueued: {
            let index = count[\.self]
            count[\.self] += 1
            queued[index].signal()
        })
        let entered = TestSignal()
        let release = TestSignal()
        let owner = Task {
            try await coordinator.withLock {
                entered.signal()
                await release.wait()
            }
        }
        await entered.wait()
        let results = TestDependencyStorage<[Int]>([])
        var tasks: [Task<Void, any Error>] = []
        for index in 0 ..< 3 {
            tasks.append(
                Task {
                    try await coordinator.withLock {
                        #expect(index != cancelIndex)
                        results[\.self].append(index)
                    }
                })
            await queued[index].wait()
        }
        tasks[cancelIndex].cancel()
        await #expect(throws: CancellationError.self) { try await tasks[cancelIndex].value }
        release.signal()
        try await owner.value
        for (index, task) in tasks.enumerated() where index != cancelIndex {
            try await task.value
        }
        #expect(results[\.self] == [0, 1, 2].filter { $0 != cancelIndex })
    }

    @Test func cancellationAtAdmissionDoesNotRunBody() async throws -> Void {
        let coordinator = ModelLifecycleCoordinator(onQueued: { withUnsafeCurrentTask { $0?.cancel() } })
        let entered = TestSignal()
        let release = TestSignal()
        let owner = Task {
            try await coordinator.withLock {
                entered.signal()
                await release.wait()
            }
        }
        await entered.wait()
        let waiter = Task {
            try await coordinator.withLock { Issue.record("Cancelled waiter ran") }
        }
        await #expect(throws: CancellationError.self) { try await waiter.value }
        release.signal()
        try await owner.value
    }
}
