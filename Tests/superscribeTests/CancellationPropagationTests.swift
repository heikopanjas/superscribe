import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Cancellation error propagation", .serialized, ResetSharedStateTrait())
struct CancellationPropagationTests {
    @Test func preservesCancellationAcrossWrappers() async -> Void {
        #expect(throws: CancellationError.self) { try Cancellation.propagate(CancellationError()) }
        #expect(throws: CancellationError.self) { try Cancellation.propagate(URLError(.cancelled)) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try Cancellation.propagate(URLError(.badURL))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
