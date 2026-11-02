import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Bounded vocal isolation", .serialized, ResetSharedStateTrait())
struct VocalIsolationTests {
    @Test func overlapsBlendAndFlushTheFinalTail() -> Void {
        var mixer = IsolationOverlap(frames: 2)
        #expect(mixer.append([1, 1, 1, 1], final: false) == [1, 1])
        let next = mixer.append([4, 4, 4, 4], final: true)
        #expect(next == [2, 3, 4, 4])
        #expect(mixer.append([], final: true).isEmpty == true)
    }

    @Test func boundsSectionsPreservesDurationAndReusesTheCache() async throws -> Void {
        let source = try TestHelpers.makeTempSineWAV(name: "isolate-sections", durationSeconds: 61.01, sampleRate: 16_000)
        defer { try? FileManager.default.removeItem(at: source) }
        try await TestHelpers.withTempDirectory { root in
            let cache = ConvertedAudioCache(root: root)
            let session = StubVocalIsolationSession()
            let count = Counter()
            let format = AudioFormat.asr16kMono
            let expected = try AudioPreparer(targetFormat: format).loadAndConvert(url: source)
            let isolator = try DemucsVocalIsolator()
            try await DemucsVocalIsolator.$openSession.withValue({ _, _ in
                await count.increment()
                return session
            }) {
                let audio = try await isolator.prepare(source: source, targetFormat: format, cache: cache, onProgress: { _ in })
                let actual = try audio.samples(in: 0 ..< Int(audio.frameCount))
                #expect(actual.count == expected.count)
                #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.00001 } == true)
                #expect(await session.sizes == [480_000, 480_000, 80_160])
                let cached = try await isolator.prepare(source: source, targetFormat: format, cache: cache, onProgress: { _ in })
                #expect(cached.url == audio.url)
                #expect(await count.value == 1)
                #expect(await session.sizes.count == 3)
                #expect(try cache.loadManifest().values.map(\.sourcePath) == [source.path])
                _ = try await isolator.prepare(source: source, targetFormat: format)
                #expect(await count.value == 1)
            }
            let normal = try #require(cache.key(for: source, targetFormat: format))
            let isolated = try #require(cache.key(for: source, targetFormat: format, processingIdentity: "htdemucs"))
            let fineTuned = try #require(cache.key(for: source, targetFormat: format, processingIdentity: "htdemucs_ft"))
            #expect(Set([normal.digest, isolated.digest, fineTuned.digest]).count == 3)
            #expect(try IsolatorModel.htdemucsFT.installPath().lastPathComponent == "htdemucs_ft")
            #expect(IsolatorModel.allCases.map { $0.demucsModel.rawValue } == ["htdemucs", "htdemucs_ft"])
        }
    }

    @Test func handlesOneFrameEmptyInputAndInvalidInference() async throws -> Void {
        for samples: [Float] in [[0.25], []] {
            let source = try TestHelpers.makeTempPCM(samples: samples, name: "isolation-short")
            defer { try? FileManager.default.removeItem(at: source) }
            let session = StubVocalIsolationSession(sampleRate: 16_000, channels: 1)
            try await DemucsVocalIsolator.$openSession.withValue(
                { _, _ in session },
                operation: {
                    let isolator = try DemucsVocalIsolator(model: .htdemucsFT, modelDirectory: source.deletingLastPathComponent())
                    let audio = try await isolator.prepare(source: source, targetFormat: .asr16kMono)
                    #expect(audio.frameCount == samples.count)
                })
        }
        let source = try TestHelpers.makeTempPCM(samples: [0.1, 0.2], name: "isolation-invalid")
        defer { try? FileManager.default.removeItem(at: source) }
        for session in [StubVocalIsolationSession(invalid: true), StubVocalIsolationSession(sampleRate: 0), StubVocalIsolationSession(channels: 3)] {
            try await DemucsVocalIsolator.$openSession.withValue(
                { _, _ in session },
                operation: {
                    let isolator = try DemucsVocalIsolator()
                    await #expect(throws: (any Error).self) { try await isolator.prepare(source: source, targetFormat: .asr16kMono) }
                })
        }
    }

    @Test func ioFailuresAndCancellationCleanUp() async throws -> Void {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await #expect(throws: (any Error).self) { try await IsolationAudioFile.open(source: missing, sampleRate: 100, channels: 2) }
        let source = try TestHelpers.makeTempSineWAV(name: "isolation-io", durationSeconds: 0.1, sampleRate: 100)
        defer { try? FileManager.default.removeItem(at: source) }
        let io = try await IsolationAudioFile.open(source: source, sampleRate: 100, channels: 2)
        await #expect(throws: (any Error).self) { try await io.read(start: io.frameCount, count: 1) }
        try await io.close()
        await #expect(throws: (any Error).self) { try await io.write([1]) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DemucsVocalIsolator().prepare(source: source, targetFormat: .asr16kMono)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancellationDuringInferenceRemovesAllTemporaryPCM() async throws -> Void {
        let source = try TestHelpers.makeTemp16kMonoFloatWAV(name: "isolation-cancel")
        defer { try? FileManager.default.removeItem(at: source) }
        let temporary = FileManager.default.temporaryDirectory
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: temporary.path).filter { $0.hasPrefix("superscribe-isolate-") })
        let entered = TestSignal()
        let release = TestSignal()
        let session = StubVocalIsolationSession(onSection: {
            entered.signal()
            await release.wait()
        })
        let task = Task {
            try await DemucsVocalIsolator.$openSession.withValue({ _, _ in session }) {
                return try await DemucsVocalIsolator().prepare(source: source, targetFormat: .asr16kMono)
            }
        }
        await entered.wait()
        task.cancel()
        release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: temporary.path).filter { $0.hasPrefix("superscribe-isolate-") })
        #expect(after == before)
    }
}
