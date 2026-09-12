import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("LoadOnce cache hit", .serialized, ResetSharedStateTrait())
struct LoadOnceCacheHitTests {
    @Test func secondGetReturnsCachedValue() async throws -> Void {
        let loader = LoadOnce<String>()
        let counter = Counter()
        let first = try await loader.get {
            await counter.increment()
            return "cached"
        }
        let second = try await loader.get {
            await counter.increment()
            return "should-not-run"
        }
        #expect(first == "cached")
        #expect(second == "cached")
        #expect(await counter.value == 1)
    }
}
