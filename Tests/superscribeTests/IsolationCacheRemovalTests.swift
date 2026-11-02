import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Isolation cache removal", .serialized, ResetSharedStateTrait())
struct IsolationCacheRemovalTests {
    @Test func removesEveryVariantAndPreservesOtherSources() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let source = root.appendingPathComponent("source.wav")
            let other = root.appendingPathComponent("other.wav")
            try Data([1]).write(to: source)
            try Data([2]).write(to: other)
            let cache = ConvertedAudioCache(root: root.appendingPathComponent("audio"))
            var files: [URL] = []
            for identity: String? in [nil, "htdemucs", "htdemucs_ft"] {
                let key = try #require(cache.key(for: source, targetFormat: .asr16kMono, processingIdentity: identity))
                files.append(try cache.store(samples: [0.1], format: .asr16kMono, key: key))
            }
            let otherKey = try #require(cache.key(for: other, targetFormat: .asr16kMono))
            let otherCache = try cache.store(samples: [0.2], format: .asr16kMono, key: otherKey)
            try cache.updateManifest(adding: .init(digest: "../other", sourcePath: source.path, storedAt: Date()))
            try FileManager.default.removeItem(at: source)
            try CacheCommand.parse([]).runRemove(path: source.path, cache: cache)
            #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) == false } == true)
            #expect(FileManager.default.fileExists(atPath: otherCache.path) == true)
            #expect(try Data(contentsOf: other) == Data([2]))
            #expect(try cache.loadManifest()[otherKey.digest] != nil)
        }
    }
}
