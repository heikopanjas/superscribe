import Foundation

public enum BoundedTaskGroupError: Error, Sendable {
    case invalidLimit
}

public enum ConcurrencyHelpers {
    /// Runs `body` for each item with at most `limit` concurrent tasks.
    /// Results are returned in the same order as `items`.
    public static func withBoundedThrowingTaskGroup<Item: Sendable, Result: Sendable>(
        limit: Int,
        items: [Item],
        body: @Sendable @escaping (Item) async throws -> Result
    ) async throws -> [Result] {
        guard limit > 0 else { throw BoundedTaskGroupError.invalidLimit }
        if items.isEmpty == true { return [] }

        return try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            var next = 0
            var inFlight = 0
            var collected: [(Int, Result)] = []

            while next < items.count || inFlight > 0 {
                while inFlight < limit && next < items.count {
                    let idx = next
                    let item = items[idx]
                    next += 1
                    inFlight += 1
                    group.addTask {
                        let result = try await body(item)
                        return (idx, result)
                    }
                }

                if let finished = try await group.next() {
                    collected.append(finished)
                    inFlight -= 1
                }
            }

            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Bounded variant when completion order does not matter.
    public static func withBoundedVoidThrowingTaskGroup<Item: Sendable>(
        limit: Int,
        items: [Item],
        body: @Sendable @escaping (Item) async throws -> Void
    ) async throws {
        _ = try await withBoundedThrowingTaskGroup(limit: limit, items: items) { item in
            try await body(item)
            return ()
        }
    }
}
