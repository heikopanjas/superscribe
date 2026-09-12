import Foundation

public enum ConcurrencyHelpers {
    /// Runs at most `limit` operations concurrently and returns results in input order.
    public static func withBoundedThrowingTaskGroup<Item: Sendable, Result: Sendable>(
        limit: Int, items: [Item], body: @Sendable @escaping (Item) async throws -> Result
    ) async throws -> [Result] {
        var results = [Result?](repeating: nil, count: items.count)
        try await Self.collect(limit: limit, items: items, body: body) { index, value in
            results[index] = .some(value)
        }
        return results.compactMap { $0 }
    }

    /// Discards completed results without retaining a result array.
    public static func withBoundedVoidThrowingTaskGroup<Item: Sendable>(
        limit: Int, items: [Item], body: @Sendable @escaping (Item) async throws -> Void
    ) async throws -> Void {
        try await Self.collect(limit: limit, items: items, body: body, onResult: { _, _ in })
    }

    internal static func collect<Item: Sendable, Result: Sendable>(
        limit: Int, items: [Item], body: @Sendable @escaping (Item) async throws -> Result,
        onResult: (Int, Result) -> Void
    ) async throws -> Void {
        guard limit > 0 else { throw BoundedTaskGroupError.invalidLimit }
        try Task.checkCancellation()
        try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            var next = 0
            func submit(_ index: Int) throws -> Void {
                try Task.checkCancellation()
                group.addTask {
                    try Task.checkCancellation()
                    return (index, try await body(items[index]))
                }
            }
            while next < min(limit, items.count) {
                try submit(next)
                next += 1
            }
            for try await (index, result) in group {
                try Task.checkCancellation()
                onResult(index, result)
                if next < items.count {
                    try submit(next)
                    next += 1
                }
            }
        }
    }
}
