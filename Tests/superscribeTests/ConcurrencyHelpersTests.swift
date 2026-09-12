import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ConcurrencyHelpers", .serialized, ResetSharedStateTrait())
struct ConcurrencyHelpersTests {
    @Test func respectsConcurrencyLimit() async throws -> Void {
        let limit = 2
        let items = Array(0 ..< 6)
        let gate = ConcurrentTestGate(batchSize: 2)

        _ = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(
            limit: limit,
            items: items
        ) { item in
            await gate.enter()
            await gate.leave()
            return item
        }

        #expect(await gate.peak == limit)
        #expect(await gate.current == 0)
    }

    @Test func preservesResultOrder() async throws -> Void {
        let results = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(
            limit: 3,
            items: [1, 2, 3, 4]
        ) { value in
            value * 10
        }
        #expect(results == [10, 20, 30, 40])
    }

    @Test func propagatesErrors() async -> Void {
        await #expect(throws: TestConcurrencyError.self) {
            _ = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(
                limit: 2,
                items: [1, 2, 3]
            ) { value in
                if value == 2 { throw TestConcurrencyError.fail }
                return value
            }
        }
    }

    @Test func rejectsNonPositiveLimit() async -> Void {
        await #expect(throws: BoundedTaskGroupError.self) {
            _ = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(
                limit: 0,
                items: [1]
            ) { $0 }
        }
    }
}
