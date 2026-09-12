import Foundation
import Testing

@testable import SuperscribeKit

@Suite("LoadOnce", .serialized, ResetSharedStateTrait())
struct LoadOnceTests {
    @Test func coalescesConcurrentLoads() async throws -> Void {
        let loader = LoadOnce<Int>()
        let counter = Counter()

        async let a: Int = loader.get {
            await counter.increment()
            return 42
        }
        async let b: Int = loader.get {
            await counter.increment()
            return 42
        }

        let results = try await [a, b]
        #expect(results == [42, 42])
        #expect(await counter.value == 1)
    }

    @Test func clearsInFlightTaskOnFailureAllowingRetry() async throws -> Void {
        let loader = LoadOnce<Int>()
        let counter = Counter()

        do {
            _ = try await loader.get {
                await counter.increment()
                throw TestError.fail
            }
        }
        catch is TestError {
            // expected
        }

        let value = try await loader.get {
            await counter.increment()
            return 7
        }
        #expect(value == 7)
        #expect(await counter.value == 2)
    }

    @Test func requireInstalledThrowsWhenMissing() -> Void {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
        #expect(throws: ModelInstallationError.self) {
            try ModelInstallSupport.requireInstalled(
                at: missing, modelId: "v3", backend: .parakeet
            )
        }
    }

    @Test func requireInstalledPassesWhenPresent() throws -> Void {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("present-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try TestHelpers.makeParakeetInstallation(at: dir)
        try ModelInstallSupport.requireInstalled(at: dir, modelId: "v3", backend: .parakeet)
        #expect(throws: ModelInstallationError.self) { try ModelInstallSupport.requireInstalled(at: dir, modelId: "en-US", backend: .appleSpeech) }
    }
}
