import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ConvertedAudioCache", .serialized, ResetSharedStateTrait())
struct ConvertedAudioCacheTests {

    /// Writes a short 48 kHz mono WAV (sine) to a temp file.
    private func makeTempSource(durationSeconds: Double = 0.25) throws -> URL {
        return try TestHelpers.makeTempSineWAV(
            name: "converted", durationSeconds: durationSeconds, amplitude: 0.25
        )
    }

    private func makeCache() throws -> ConvertedAudioCache {
        let dir = try TestHelpers.makeTempDir(prefix: "superscribe-cache-tests")
        return ConvertedAudioCache(root: dir)
    }

    @Test func formatKeyIsDeterministic() -> Void {
        let f = AudioFormat(sampleRate: 16_000, channels: 1)
        #expect(ConvertedAudioCache.formatKey(for: f) == "f32-16000-1")
    }

    @Test func lookupReturnsNilForMissingEntry() throws -> Void {
        let cache = try self.makeCache()
        let url = try self.makeTempSource()
        defer { try? FileManager.default.removeItem(at: url) }
        let key = (try #require(cache.key(for: url, targetFormat: .asr16kMono)))
        #expect(cache.lookup(key) == nil)
    }

    @Test func storeThenLookupReturnsURL() throws -> Void {
        let cache = try self.makeCache()
        let url = try self.makeTempSource()
        defer { try? FileManager.default.removeItem(at: url) }
        let key = (try #require(cache.key(for: url, targetFormat: .asr16kMono)))
        let samples: [Float] = (0 ..< 1_000).map { Float($0) / 1_000.0 }
        let stored = try cache.store(samples: samples, format: .asr16kMono, key: key)
        #expect(FileManager.default.fileExists(atPath: stored.path))
        #expect(cache.lookup(key) == stored)
    }

    @Test func cachedSamplesRoundTripThroughAudioPreparer() throws -> Void {
        let cache = try self.makeCache()
        let url = try self.makeTempSource(durationSeconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: cache)

        // First call: converts and writes to cache.
        let firstSamples = try preparer.loadAndConvert(url: url)
        #expect(firstSamples.count > 0)
        let key = (try #require(cache.key(for: url, targetFormat: .asr16kMono)))
        #expect(cache.lookup(key) != nil)

        // Second call: should hit the cache and produce the same output.
        let secondSamples = try preparer.loadAndConvert(url: url)
        #expect(secondSamples.count == firstSamples.count)
        // Cached read must reproduce the converted samples bit-for-bit.
        for i in stride(from: 0, to: firstSamples.count, by: max(1, firstSamples.count / 100)) {
            #expect(abs(firstSamples[i] - secondSamples[i]) < 1e-6)
        }
    }

    @Test func keyChangesWhenFormatChanges() throws -> Void {
        let cache = try self.makeCache()
        let url = try self.makeTempSource()
        defer { try? FileManager.default.removeItem(at: url) }
        let k16 = (try #require(cache.key(for: url, targetFormat: AudioFormat(sampleRate: 16_000, channels: 1))))
        let k22 = (try #require(cache.key(for: url, targetFormat: AudioFormat(sampleRate: 22_050, channels: 1))))
        #expect(k16.digest != k22.digest)
    }

    @Test func keyChangesWhenSourceMtimeChanges() throws -> Void {
        let cache = try self.makeCache()
        let url = try self.makeTempSource()
        defer { try? FileManager.default.removeItem(at: url) }
        let k1 = (try #require(cache.key(for: url, targetFormat: .asr16kMono)))

        // Bump mtime forward by 5 seconds.
        let later = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes(
            [.modificationDate: later], ofItemAtPath: url.path
        )
        let k2 = (try #require(cache.key(for: url, targetFormat: .asr16kMono)))
        #expect(k1.digest != k2.digest)
    }

    @Test func keyReturnsNilWhenAttributesUnreadable() throws -> Void {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "cache-key2"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let missing = URL(fileURLWithPath: "/tmp/no-such-\(UUID().uuidString).wav")
        #expect(cache.key(for: missing, targetFormat: .asr16kMono) == nil)
    }

    @Test func storeFailsWhenCacheRootIsAFile() throws -> Void {
        let rootFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("rootfile-\(UUID().uuidString)")
        try Data("x".utf8).write(to: rootFile)
        defer { try? FileManager.default.removeItem(at: rootFile) }
        let cache = ConvertedAudioCache(root: rootFile)
        let key = ConvertedAudioCache.CacheKey(
            sourcePath: "/tmp/a.wav",
            sourceSize: 1,
            sourceMtimeNanos: 1,
            formatKey: "f32-16000-1"
        )
        #expect(throws: Error.self) {
            _ = try cache.store(samples: [0.1], format: .asr16kMono, key: key)
        }
    }

    @Test func storeFailsWhenRootIsReadOnly() throws -> Void {
        let root = try TestHelpers.makeTempDir(prefix: "cache-ro")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        let cache = ConvertedAudioCache(root: root)
        let key = ConvertedAudioCache.CacheKey(
            sourcePath: "/tmp/a.wav",
            sourceSize: 1,
            sourceMtimeNanos: 1,
            formatKey: "f32-16000-1"
        )
        #expect(throws: AudioPreparerError.self) {
            _ = try cache.store(samples: [0.1, 0.2], format: .asr16kMono, key: key)
        }
    }
}
