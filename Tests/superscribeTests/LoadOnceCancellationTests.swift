import Testing

@testable import SuperscribeKit

@Suite("LoadOnce cancellation", .serialized, ResetSharedStateTrait())
struct LoadOnceCancellationTests {
    @Test func cancellationDuringRegistrationDoesNotLeaveAWaiter() async -> Void {
        SuperscribeKitTestHooks.loadWaiterWillRegister = {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let task = Task {
            return try await LoadOnce<Int>().get {
                Issue.record("Cancelled load ran")
                return 1
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func cancellingOneWaiterKeepsSharedLoadAlive() async throws -> Void {
        let loader = LoadOnce<Int>()
        let firstAdded = TestSignal()
        let secondAdded = TestSignal()
        let release = TestSignal()
        let count = TestDependencyStorage(0)
        SuperscribeKitTestHooks.loadWaiterWillRegister = {
            count[\.self] += 1
            if count[\.self] == 1 {
                firstAdded.signal()
            }
            else {
                secondAdded.signal()
            }
        }
        let first = Task {
            return try await loader.get {
                await release.wait()
                try Task.checkCancellation()
                return 42
            }
        }
        await firstAdded.wait()
        let second = Task {
            return try await loader.get {
                Issue.record("Shared load restarted")
                return 0
            }
        }
        await secondAdded.wait()
        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        release.signal()
        #expect(try await second.value == 42)
    }

    @Test func lastWaiterCancelsLoadAndLateResultCannotReplaceRetry() async throws -> Void {
        let loader = LoadOnce<Int>()
        let entered = TestSignal()
        let release = TestSignal()
        let finished = TestSignal()
        let first = Task {
            return try await loader.get {
                entered.signal()
                await release.wait()
                #expect(Task.isCancelled == true)
                finished.signal()
                return 1
            }
        }
        await entered.wait()
        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        #expect(try await loader.get { return 2 } == 2)
        release.signal()
        await finished.wait()
        #expect(try await loader.get { return 3 } == 2)
    }

    @Test func cancelledCallerDoesNotStartLoading() async -> Void {
        let loader = LoadOnce<Int>()
        let entered = TestSignal()
        let proceed = TestSignal()
        let task = Task {
            entered.signal()
            await proceed.wait()
            return try await loader.get {
                Issue.record("Cancelled load ran")
                return 1
            }
        }
        await entered.wait()
        task.cancel()
        proceed.signal()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
