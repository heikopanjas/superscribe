import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Audio cache publication", .serialized, ResetSharedStateTrait())
struct AudioCachePublicationTests {
    @Test(arguments: [false, true])
    func manifestFailureDoesNotRepeatConversion(streaming: Bool) throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let source = try TestHelpers.makeTemp16kMonoFloatWAV(name: "manifest-failure")
            defer { try? FileManager.default.removeItem(at: source) }
            let expected = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: source)
            let cache = ConvertedAudioCache(root: root)
            let key = try #require(cache.key(for: source, targetFormat: .asr16kMono))
            // A directory at the lock path prevents manifest writes without blocking audio publication.
            let blocker = cache.manifestURL.appendingPathExtension("lock")
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
            let lock = NSLock()
            nonisolated(unsafe) var conversions = 0
            let dependencies = AudioBuffers.Dependencies(
                read: { file, buffer, count in
                    if file.url == source, file.framePosition == 0 { lock.withLock { conversions += 1 } }
                    try file.read(into: buffer, frameCount: count)
                })
            try AudioBuffers.$dependencies.withValue(dependencies) {
                let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: cache)
                let audio: PreparedAudio
                if streaming == true {
                    audio = try preparer.prepare(url: source)
                }
                else {
                    let path = try cache.store(samples: expected, format: .asr16kMono, key: key)
                    audio = try PreparedAudio(url: path, format: .asr16kMono, temporary: false)
                }
                #expect(audio.url == cache.cacheURL(for: key))
                #expect(try audio.samples(in: 0 ..< Int(audio.frameCount)) == expected)
                #expect(conversions == (streaming ? 1 : 0))
                let cached = try preparer.prepare(url: source)
                #expect(cached.url == cache.cacheURL(for: key))
                #expect(try cached.samples(in: 0 ..< Int(cached.frameCount)) == expected)
                #expect(conversions == (streaming ? 1 : 0))
            }
            #expect(try cache.loadManifest().isEmpty == true)
            let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(contents.contains(where: { $0.contains(".staging-") }) == false)
        }
    }

    @Test(arguments: [false, true])
    func failedReplacementPreservesPublishedAudioAndManifest(duringWrite: Bool) throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let cache = ConvertedAudioCache(root: root)
            let key = ConvertedAudioCache.CacheKey(sourcePath: "/source.wav", sourceSize: 1, sourceMtimeNanos: 1, formatKey: ConvertedAudioCache.formatKey(for: .asr16kMono))
            let original = try cache.store(samples: [0.1, 0.2], format: .asr16kMono, key: key)
            let audio = try Data(contentsOf: original)
            let manifest = try Data(contentsOf: cache.manifestURL)
            SuperscribeKitTestHooks.forceCacheStoreAtomicReplaceFailure = duringWrite == false
            SuperscribeKitTestHooks.forceCacheStoreMidWriteFailure = duringWrite
            #expect(throws: CocoaError.self) { _ = try cache.store(samples: [0.3], format: .asr16kMono, key: key) }
            #expect(try Data(contentsOf: original) == audio)
            #expect(try Data(contentsOf: cache.manifestURL) == manifest)
            let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(contents.contains(where: { $0.contains(".staging-") }) == false)
        }
    }
}
