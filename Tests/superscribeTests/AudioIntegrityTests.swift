import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Audio integrity", .serialized, ResetSharedStateTrait())
struct AudioIntegrityTests {
    @Test func readFailureCannotPublishPartialAudio() async throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let source = try TestHelpers.makeTempSineWAV(name: "truncated", durationSeconds: 2)
            defer { try? FileManager.default.removeItem(at: source) }
            let cache = ConvertedAudioCache(root: root)
            let key = try #require(cache.key(for: source, targetFormat: .asr16kMono))
            SuperscribeKitTestHooks.audioReadFailureAfterFrames = 48_000
            #expect(throws: CocoaError.self) {
                _ = try AudioPreparer(targetFormat: .asr16kMono, cache: cache).loadAndConvert(url: source) { progress in
                    #expect(progress.fraction < 1)
                }
            }
            #expect(cache.lookup(key) == nil)
        }
    }

    @Test func converterErrorWithoutNSErrorStillFails() throws -> Void {
        let source = try TestHelpers.makeTempSineWAV(name: "converter-error")
        defer { try? FileManager.default.removeItem(at: source) }
        SuperscribeKitTestHooks.audioConverterErrorWithoutDetails = true
        #expect(throws: AudioPreparerError.self) { _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: source) }
    }

    @Test func corruptCacheIsReconverted() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let source = try TestHelpers.makeTempSineWAV(name: "recovery", durationSeconds: 0.2)
            defer { try? FileManager.default.removeItem(at: source) }
            let cache = ConvertedAudioCache(root: root)
            let key = try #require(cache.key(for: source, targetFormat: .asr16kMono))
            try Data("not audio".utf8).write(to: cache.cacheURL(for: key))
            let samples = try AudioPreparer(targetFormat: .asr16kMono, cache: cache).loadAndConvert(url: source)
            #expect(samples.isEmpty == false)
            #expect(try Data(contentsOf: cache.cacheURL(for: key)) != Data("not audio".utf8))
        }
    }

    @Test(arguments: [AudioFormat(sampleRate: 0, channels: 1), AudioFormat(sampleRate: 16_000, channels: 2)])
    func invalidFormatFailsBeforeOpeningMedia(format: AudioFormat) -> Void {
        #expect(throws: AudioPreparerError.self) {
            _ = try AudioPreparer(targetFormat: format).loadAndConvert(url: URL(fileURLWithPath: "/missing"))
        }
    }

    @Test(arguments: [Double.nan, .infinity, -1, Double(UInt32.max) + 1])
    func invalidFrameCountThrows(value: Double) -> Void {
        #expect(throws: AudioPreparerError.self) { _ = try AudioValidation.frameCount(value) }
    }

    @Test func sliceValidatesTimesAndClampsFiniteExtremes() throws -> Void {
        let preparer = AudioPreparer(targetFormat: .asr16kMono)
        #expect(throws: AudioPreparerError.self) { _ = try preparer.slice([1], segment: SpeechSegment(start: .nan, end: 1)) }
        #expect(throws: AudioPreparerError.self) { _ = try preparer.slice([1], segment: SpeechSegment(start: 2, end: 1)) }
        #expect(try preparer.slice([1], segment: SpeechSegment(start: -Double.greatestFiniteMagnitude, end: Double.greatestFiniteMagnitude)) == [1])
        #expect(try preparer.slice([1], segment: SpeechSegment(start: 3, end: 4)).isEmpty == true)
    }
}
