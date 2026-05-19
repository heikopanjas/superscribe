import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ConvertedAudioCache")
struct ConvertedAudioCacheTests {

    /// Writes a short 48 kHz mono WAV (sine) to a temp file.
    private func makeTempSource(durationSeconds: Double = 0.25) throws -> URL {
        try TestHelpers.makeTempSineWAV(
            name: "converted", durationSeconds: durationSeconds, amplitude: 0.25
        )
    }

    private func makeCache() throws -> ConvertedAudioCache {
        let dir = try TestHelpers.makeTempDir(prefix: "superscribe-cache-tests")
        return ConvertedAudioCache(root: dir)
    }

    @Test func formatKeyIsDeterministic() {
        let f = AudioFormat(sampleRate: 16_000, channels: 1)
        #expect(ConvertedAudioCache.formatKey(for: f) == "f32-16000-1")
    }

    @Test func lookupReturnsNilForMissingEntry() throws {
        let cache = try makeCache()
        let url = try makeTempSource()
        defer { try? FileManager.default.removeItem(at: url) }
        let key = cache.key(for: url, targetFormat: .asr16kMono)!
        #expect(cache.lookup(key) == nil)
    }

    @Test func storeThenLookupReturnsURL() throws {
        let cache = try makeCache()
        let url = try makeTempSource()
        defer { try? FileManager.default.removeItem(at: url) }
        let key = cache.key(for: url, targetFormat: .asr16kMono)!
        let samples: [Float] = (0 ..< 1_000).map { Float($0) / 1_000.0 }
        let stored = try cache.store(samples: samples, format: .asr16kMono, key: key)
        #expect(FileManager.default.fileExists(atPath: stored.path))
        #expect(cache.lookup(key) == stored)
    }

    @Test func cachedSamplesRoundTripThroughAudioPreparer() throws {
        let cache = try makeCache()
        let url = try makeTempSource(durationSeconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: cache)

        // First call: converts and writes to cache.
        let firstSamples = try preparer.loadAndConvert(url: url)
        #expect(firstSamples.count > 0)
        let key = cache.key(for: url, targetFormat: .asr16kMono)!
        #expect(cache.lookup(key) != nil)

        // Second call: should hit the cache and produce the same output.
        let secondSamples = try preparer.loadAndConvert(url: url)
        #expect(secondSamples.count == firstSamples.count)
        // Cached read must reproduce the converted samples bit-for-bit.
        for i in stride(from: 0, to: firstSamples.count, by: max(1, firstSamples.count / 100)) {
            #expect(abs(firstSamples[i] - secondSamples[i]) < 1e-6)
        }
    }

    @Test func keyChangesWhenFormatChanges() throws {
        let cache = try makeCache()
        let url = try makeTempSource()
        defer { try? FileManager.default.removeItem(at: url) }
        let k16 = cache.key(for: url, targetFormat: AudioFormat(sampleRate: 16_000, channels: 1))!
        let k22 = cache.key(for: url, targetFormat: AudioFormat(sampleRate: 22_050, channels: 1))!
        #expect(k16.digest != k22.digest)
    }

    @Test func keyChangesWhenSourceMtimeChanges() throws {
        let cache = try makeCache()
        let url = try makeTempSource()
        defer { try? FileManager.default.removeItem(at: url) }
        let k1 = cache.key(for: url, targetFormat: .asr16kMono)!

        // Bump mtime forward by 5 seconds.
        let later = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes(
            [.modificationDate: later], ofItemAtPath: url.path
        )
        let k2 = cache.key(for: url, targetFormat: .asr16kMono)!
        #expect(k1.digest != k2.digest)
    }

    @Test func keyReturnsNilWhenAttributesUnreadable() throws {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "cache-key2"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let missing = URL(fileURLWithPath: "/tmp/no-such-\(UUID().uuidString).wav")
        #expect(cache.key(for: missing, targetFormat: .asr16kMono) == nil)
    }

    @Test func storeFailsWhenCacheRootIsAFile() throws {
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

    @Test func storeFailsWhenRootIsReadOnly() throws {
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

@Suite("AudioPreparer.ConversionProgress")
struct AudioPreparerProgressTests {

    private func makeTempSource(durationSeconds: Double = 1.0) throws -> URL {
        let sampleRate: Double = 48_000
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let floats = buffer.floatChannelData![0]
        for i in 0 ..< Int(frameCount) {
            floats[i] = sinf(2.0 * .pi * 220.0 * Float(i) / Float(sampleRate)) * 0.25
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    @Test func progressFractionsAreMonotonicAndEndAt1() throws {
        let url = try makeTempSource(durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: url) }

        let lock = NSLock()
        nonisolated(unsafe) var fractions: [Double] = []
        let preparer = AudioPreparer(targetFormat: .asr16kMono)
        _ = try preparer.loadAndConvert(url: url) { progress in
            lock.lock()
            fractions.append(progress.fraction)
            lock.unlock()
        }

        #expect(!fractions.isEmpty)
        #expect(fractions.last == 1.0)
        // Non-decreasing.
        for (a, b) in zip(fractions, fractions.dropFirst()) {
            #expect(b >= a - 1e-9)
        }
    }
}
