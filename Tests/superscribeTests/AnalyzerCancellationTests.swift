import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Speech detection cancellation", .serialized, ResetSharedStateTrait())
struct AnalyzerCancellationTests {
    @Test(arguments: [false, true])
    func pipelineStopsReadingAndCleansTemporaryAudio(cancel: Bool) async throws -> Void {
        let source = try TestHelpers.makeTempSineWAV(name: "detection-cancel", durationSeconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let config = AnalyzerConfig()
        let gate = BlockingTestGate(batchSize: 1)
        let calls = Counter()
        let lock = NSLock()
        nonisolated(unsafe) var reads = 0
        nonisolated(unsafe) var preparedURL: URL?
        let dependencies = AudioBuffers.Dependencies(
            read: { file, buffer, count in
                if file.url != source, count <= AVAudioFrameCount(config.windowSize) {
                    let first = lock.withLock {
                        reads += 1
                        preparedURL = file.url
                        return reads == 1
                    }
                    if first == true { gate.enter() }
                }
                try file.read(into: buffer, frameCount: count)
            })
        let transcriber = ControlledTranscriber { segment in
            await calls.increment()
            return [.init(text: "speech", start: segment.start, end: segment.end)]
        }
        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: .init(tracks: [.init(speaker: "A", file: source)], transcriptionConfig: .init(), analyzerConfig: config))
        let task = Task {
            return try await AudioBuffers.$dependencies.withValue(dependencies) { try await pipeline.run() }
        }
        await gate.initialBatch.wait()
        #expect(gate.current == 1)
        if cancel == true { task.cancel() }
        gate.release()
        if cancel == true {
            await #expect(throws: CancellationError.self) { _ = try await task.value }
            #expect(reads == 1)
            #expect(await calls.value == 0)
        }
        else {
            #expect(try await task.value.tracks.count == 1)
            #expect(reads > 1)
            #expect(await calls.value == 1)
        }
        #expect(gate.current == 0)
        let prepared = try #require(preparedURL)
        #expect(FileManager.default.fileExists(atPath: prepared.path) == false)
        #expect(FileManager.default.fileExists(atPath: source.path) == true)
    }

    @Test(arguments: [false, true])
    func publicDetectionHonorsTaskCancellation(fileBacked: Bool) async throws -> Void {
        let source = try TestHelpers.makeTemp16kMonoFloatWAV(name: "direct-detection-cancel")
        defer { try? FileManager.default.removeItem(at: source) }
        let audio = try AudioPreparer(targetFormat: .asr16kMono).prepare(url: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return if fileBacked == true { try Analyzer().detectSpeech(in: audio) }
            else { try Analyzer().detectSpeech(samples: [0.1], sampleRate: 16_000) }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
