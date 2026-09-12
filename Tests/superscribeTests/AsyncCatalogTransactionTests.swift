import Darwin
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Async catalog transactions", .serialized, ResetSharedStateTrait())
struct AsyncCatalogTransactionTests {
    @Test func asynchronousUpdatesRetainEveryBackend() async throws -> Void {
        let entry = CatalogEntry(fetchedAt: Date(timeIntervalSince1970: 0), models: [])
        try await ConcurrencyHelpers.withBoundedVoidThrowingTaskGroup(limit: 3, items: Backend.allCases) { backend in
            try await CatalogStore.updateAsync(entry, for: backend)
        }
        let catalog = try CatalogStore.load()
        for backend in Backend.allCases { #expect(catalog.entry(for: backend) != nil) }
    }
}
