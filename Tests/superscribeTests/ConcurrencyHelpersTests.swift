import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ConcurrencyHelpers")
struct ConcurrencyHelpersTests {
    @Test func respectsConcurrencyLimit() async throws {
        let limit = 2
        let items = Array(0 ..< 6)
        let gate = InFlightGate()

        _ = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(
            limit: limit,
            items: items
        ) { item in
            await gate.enter()
            defer { Task { await gate.leave() } }
            try await Task.sleep(for: .milliseconds(20))
            return item
        }

        #expect(await gate.peak <= limit)
    }

    @Test func preservesResultOrder() async throws {
        let results = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(
            limit: 3,
            items: [1, 2, 3, 4]
        ) { value in
            value * 10
        }
        #expect(results == [10, 20, 30, 40])
    }

    @Test func propagatesErrors() async {
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
}

private enum TestConcurrencyError: Error { case fail }

private actor InFlightGate {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}
