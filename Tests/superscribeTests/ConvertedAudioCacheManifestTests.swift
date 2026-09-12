import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - ConvertedAudioCache

@Suite("ConvertedAudioCache manifest", .serialized, ResetSharedStateTrait())
struct ConvertedAudioCacheManifestTests {
    @Test func defaultRootUsesSuperscribePaths() throws -> Void {
        let cache = ConvertedAudioCache()
        #expect(cache.root == SuperscribePaths.audioCacheRoot())
    }

    @Test func keyReturnsNilForMissingFile() throws -> Void {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "cache-key"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let missing = URL(fileURLWithPath: "/tmp/no-such-\(UUID().uuidString).wav")
        #expect(cache.key(for: missing, targetFormat: .asr16kMono) == nil)
    }

    @Test func manifestRoundTripAndRemoval() throws -> Void {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "manifest"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let entry = ConvertedAudioCache.ManifestEntry(
            digest: "abc123",
            sourcePath: "/tmp/source.wav",
            storedAt: Date(timeIntervalSince1970: 100)
        )
        try cache.updateManifest(adding: entry)
        let loaded = try cache.loadManifest()
        #expect(loaded["abc123"]?.sourcePath == "/tmp/source.wav")
        try cache.updateManifest(removingDigest: "abc123")
        #expect(try cache.loadManifest().isEmpty == true)
        try cache.updateManifest(removingDigest: "missing")  // no-op
    }
}
