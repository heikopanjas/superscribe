import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - AudioPreparer

@Suite("AudioPreparer edge cases", .serialized, ResetSharedStateTrait())
struct AudioPreparerEdgeTests {
    @Test func errorDescriptions() throws -> Void {
        let url = URL(fileURLWithPath: "/tmp/x.wav")
        #expect(AudioPreparerError.cannotReadFile(url, underlying: URLError(.badURL)).description.contains("Cannot read") == true)
        #expect(AudioPreparerError.unsupportedFormat(url).description.contains("Unsupported") == true)
        #expect(AudioPreparerError.conversionFailed("boom").description.contains("boom") == true)
    }

    @Test func cannotReadMissingSource() throws -> Void {
        let url = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).wav")
        let preparer = AudioPreparer(targetFormat: .asr16kMono)
        #expect(throws: AudioPreparerError.self) { _ = try preparer.loadAndConvert(url: url) }
    }

    @Test func fastPathWhenSourceMatchesTargetFormat() throws -> Void {
        let url = try TestHelpers.makeTemp16kMonoFloatWAV(name: "fast-path")
        defer { try? FileManager.default.removeItem(at: url) }
        let preparer = AudioPreparer(targetFormat: .asr16kMono)
        let samples = try preparer.loadAndConvert(url: url)
        #expect(samples.isEmpty == false)
    }

    @Test func cacheWriteFailureIsNonFatal() throws -> Void {
        let url = try TestHelpers.makeTempSineWAV(name: "cache-fail", durationSeconds: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let cache = ConvertedAudioCache(root: blocker)
        let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: cache)
        let samples = try preparer.loadAndConvert(url: url)
        #expect(samples.isEmpty == false)
    }

    @Test func loadCachedRecoversWhenCacheFileCorrupt() throws -> Void {
        let url = try TestHelpers.makeTempSineWAV(name: "cached-bad", durationSeconds: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        let cacheRoot = try TestHelpers.makeTempDir(prefix: "cache-root")
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let cache = ConvertedAudioCache(root: cacheRoot)
        let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: cache)
        _ = try preparer.loadAndConvert(url: url)
        let key = (try #require(cache.key(for: url, targetFormat: .asr16kMono)))
        let cachedURL = try #require(cache.lookup(key))
        try Data("not-a-wav".utf8).write(to: cachedURL)
        #expect(try preparer.loadAndConvert(url: url).isEmpty == false)
    }
}
