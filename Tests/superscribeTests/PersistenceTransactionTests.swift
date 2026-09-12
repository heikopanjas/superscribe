import Darwin
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Persistence transactions", .serialized, ResetSharedStateTrait())
struct PersistenceTransactionTests {
    @Test func concurrentManifestUpdatesRetainEveryEntry() async throws -> Void {
        try await TestHelpers.withTempDirectory { root in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0 ..< 20 {
                    group.addTask {
                        let worker = BlockingWorker(label: "superscribe.transaction.\(index)")
                        try await worker.run { _ in
                            let cache = ConvertedAudioCache(root: root)
                            try cache.updateManifest(adding: .init(digest: String(index), sourcePath: "/audio/\(index)", storedAt: Date()))
                        }
                    }
                }
                try await group.waitForAll()
            }
            #expect(try ConvertedAudioCache(root: root).loadManifest().count == 20)
        }
    }

    @Test func configurationUpdatesPreserveOtherFields() async throws -> Void {
        async let backend: Void = UserConfig.update { $0.setDefaultBackend(.whisperCpp) }
        async let model: Void = UserConfig.update { $0.setDefaultModel("v2", for: .parakeet) }
        _ = try await (backend, model)
        let config = try UserConfig.load()
        #expect(config.resolvedDefaultBackend() == .whisperCpp)
        #expect(config.defaultModel(for: .parakeet) == "v2")
    }

    @Test func corruptConfigurationIsPreserved() async throws -> Void {
        let url = UserConfig.configFileURL
        let corrupt = Data("{bad".utf8)
        try corrupt.write(to: url)
        #expect(throws: DecodingError.self) { _ = try UserConfig.load() }
        await #expect(throws: DecodingError.self) {
            try await UserConfig.update { $0.setDefaultBackend(.whisperCpp) }
        }
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func lockOpenFailurePreservesData() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let url = root.appendingPathComponent("data")
            try Data("old".utf8).write(to: url)
            try FileManager.default.createDirectory(at: url.appendingPathExtension("lock"), withIntermediateDirectories: true)
            #expect(throws: (any Error).self) {
                try FileTransaction.withLock(for: url) { try Data("new".utf8).write(to: url) }
            }
            #expect(try Data(contentsOf: url) == Data("old".utf8))
        }
    }

    @Test func lockFailurePreventsMutation() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            FileTransaction.$lockOperation.withValue(
                { _, _ in return -1 },
                operation: {
                    _ = #expect(throws: (any Error).self) {
                        try FileTransaction.withLock(for: root.appendingPathComponent("data")) {
                            Issue.record("Mutation ran without owning the lock")
                        }
                    }
                })
        }
    }
}
