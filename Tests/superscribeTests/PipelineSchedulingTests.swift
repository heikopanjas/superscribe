import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Global pipeline scheduling", .serialized, ResetSharedStateTrait())
struct PipelineSchedulingTests {
    @Test func countsCompletionsRatherThanSegmentIdentity() async throws -> Void {
        let urls = try (1 ... 3).map { try TestHelpers.makeTempSineWAV(name: "order-\($0)", durationSeconds: Double($0)) }
        defer { for url in urls { try? FileManager.default.removeItem(at: url) } }
        let entries = (0 ..< 3).map { _ in TestSignal() }
        let releases = (0 ..< 3).map { _ in TestSignal() }
        let completions = (0 ..< 3).map { _ in TestSignal() }
        let ticks = TestDependencyStorage<[TranscriptionProgress]>([])
        let transcriber = ControlledTranscriber { segment in
            let index = Int(segment.end.rounded()) - 1
            entries[index].signal()
            await releases[index].wait()
            return [.init(text: "word-\(index)", start: segment.start, end: segment.end)]
        }
        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: .init(tracks: urls.enumerated().map { TrackInput(speaker: "\($0.offset)", file: $0.element) }, transcriptionConfig: .init(), maxConcurrentTranscriptions: 3),
            onProgress: { progress in
                var values = ticks[\.self]
                values.append(progress)
                ticks[\.self] = values
                completions[progress.overallCompleted - 1].signal()
            })
        let task = Task { try await pipeline.run() }
        for entry in entries { await entry.wait() }
        for (completion, index) in [2, 0, 1].enumerated() {
            releases[index].signal()
            await completions[completion].wait()
        }
        let result = try await task.value
        #expect(ticks[\.self].map(\.overallCompleted) == [1, 2, 3])
        #expect(ticks[\.self].map(\.speaker) == ["2", "0", "1"])
        #expect(result.tracks.map(\.speaker) == ["0", "1", "2"])
    }
    @Test func outOfOrderSegmentsReportActualCompletionCount() async throws -> Void {
        let samples = (0 ..< 80_000).map { Float(($0 / 16_000) % 2 == 0 ? 0.5 : 0) }
        let source = try TestHelpers.makeTempPCM(samples: samples, name: "ordered-segments")
        defer { try? FileManager.default.removeItem(at: source) }
        let entries = (0 ..< 3).map { _ in TestSignal() }
        let releases = (0 ..< 3).map { _ in TestSignal() }
        let completions = (0 ..< 3).map { _ in TestSignal() }
        let ticks = TestDependencyStorage<[TranscriptionProgress]>([])
        let transcriber = ControlledTranscriber { segment in
            let index = Int(segment.start) / 2
            entries[index].signal()
            await releases[index].wait()
            return [.init(text: "word-\(index)", start: segment.start, end: segment.end)]
        }
        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: .init(tracks: [.init(speaker: "A", file: source)], transcriptionConfig: .init(), analyzerConfig: .init(padding: 0, windowSize: 1600), maxConcurrentTranscriptions: 3),
            onProgress: { progress in
                ticks[\.self].append(progress)
                completions[progress.overallCompleted - 1].signal()
            })
        let task = Task { try await pipeline.run() }
        for entry in entries { await entry.wait() }
        for (completion, index) in [2, 0, 1].enumerated() {
            releases[index].signal()
            await completions[completion].wait()
        }
        let transcript = try await task.value
        #expect(ticks[\.self].map(\.segmentIndex) == [3, 1, 2])
        #expect(ticks[\.self].map(\.overallCompleted) == [1, 2, 3])
        #expect(transcript.tracks[0].segments.flatMap(\.words).map(\.text) == ["word-0", "word-1", "word-2"])
    }
}
