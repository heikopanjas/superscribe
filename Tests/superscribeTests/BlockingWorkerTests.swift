import Testing

@testable import SuperscribeKit

@Suite("Blocking worker")
struct BlockingWorkerTests {
    @Test func nestedLifetimeCleanupDoesNotDeadlock() async throws -> Void {
        let worker = BlockingWorker(label: "superscribe.worker.tests")
        #expect(try await worker.run { _ in return worker.sync { return 42 } } == 42)
        #expect(worker.sync { return 7 } == 7)
    }

    @Test func cancelledAdmissionSkipsWork() async -> Void {
        let worker = BlockingWorker(label: "superscribe.worker.cancel")
        let entered = TestSignal()
        let proceed = TestSignal()
        let task = Task {
            entered.signal()
            await proceed.wait()
            return try await worker.run { _ in
                Issue.record("Cancelled work was admitted")
                return 1
            }
        }
        await entered.wait()
        task.cancel()
        proceed.signal()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
