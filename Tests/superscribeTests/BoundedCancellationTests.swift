import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Bounded admission cancellation")
struct BoundedCancellationTests {
    @Test func preservesNilResults() async throws -> Void {
        let result: [Int?] = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(limit: 2, items: [1, 2]) { value in
            return value == 1 ? nil : value
        }
        #expect(result.count == 2)
        #expect(result[0] == nil)
        #expect(result[1] == 2)
    }

    @Test func cancellationStopsFurtherAdmission() async -> Void {
        let entered = TestSignal()
        let release = TestSignal()
        let task = Task {
            try await ConcurrencyHelpers.withBoundedVoidThrowingTaskGroup(limit: 1, items: [0, 1, 2]) { item in
                #expect(item == 0)
                entered.signal()
                await release.wait()
            }
        }
        await entered.wait()
        task.cancel()
        release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
