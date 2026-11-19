import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Pipeline", .serialized, ResetSharedStateTrait())
struct PipelineTests {
    @Test("pipeline produces intermediate transcript from two tracks")
    func twoTracks() async throws -> Void {
        let aliceURL = try TestHelpers.makeTempSineWAV(name: "Alice", durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: aliceURL) }
        let bobURL = try TestHelpers.makeTempSineWAV(name: "Bob", durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: bobURL) }

        let transcript = try await TestHelpers.runMockPipeline(tracks: [
            TrackInput(speaker: "Alice", file: aliceURL),
            TrackInput(speaker: "Bob", file: bobURL)
        ])

        #expect(transcript.version == IntermediateTranscript.currentVersion)
        #expect(transcript.tracks.count == 2)

        let speakers = Set(transcript.tracks.map(\.speaker))
        #expect(speakers == ["Alice", "Bob"])

        // Each track should have at least one segment (the Analyzer will
        // detect the sine wave as speech).
        for track in transcript.tracks {
            #expect(!track.segments.isEmpty, "Track \(track.speaker) should have segments")
            for seg in track.segments {
                #expect(!seg.words.isEmpty, "Segment should have words from MockTranscriber")
            }
        }
    }

    @Test("intermediate transcript round-trips through JSON")
    func jsonRoundTrip() async throws -> Void {
        let url = try TestHelpers.makeTempSineWAV(name: "Solo", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: url) }

        let original = try await TestHelpers.runMockPipeline(
            tracks: [TrackInput(speaker: "Solo", file: url)],
            language: nil
        )

        let data = try IntermediateTranscript.jsonEncoder().encode(original)
        let decoded = try IntermediateTranscript.jsonDecoder().decode(
            IntermediateTranscript.self, from: data
        )

        #expect(decoded.version == original.version)
        #expect(decoded.tracks.count == original.tracks.count)
        #expect(decoded.tracks.first?.speaker == "Solo")
        #expect(decoded.tracks.first?.segments.count == original.tracks.first?.segments.count)
    }

    @Test("pipeline metadata records configured backend")
    func backendMetadata() async throws -> Void {
        let url = try TestHelpers.makeTempSineWAV(name: "Backend", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: url) }

        let transcript = try await TestHelpers.runMockPipeline(
            tracks: [TrackInput(speaker: "Solo", file: url)],
            backend: .whisperCpp,
            model: "large-v3-turbo"
        )
        #expect(transcript.metadata.backend == .whisperCpp)
        #expect(transcript.metadata.model == "large-v3-turbo")
    }

    @Test("empty segment samples do not invoke transcriber")
    func emptySegmentSkipsTranscriber() async throws -> Void {
        let counter = Counter()
        let transcriber = ControlledTranscriber { segment in
            await counter.increment()
            return [.init(text: "x", start: segment.start, end: segment.end)]
        }
        let source = try TestHelpers.makeTempPCM(samples: [0.1], name: "empty-segment")
        defer { try? FileManager.default.removeItem(at: source) }
        let ticks = TestDependencyStorage<[TranscriptionProgress]>([])

        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: PipelineConfig(
                tracks: [TrackInput(speaker: "Solo", file: source, diarization: TrackDiarization())],
                backend: .parakeet,
                transcriptionConfig: TranscriptionConfig(language: "en", prompt: nil),
                analyzerConfig: AnalyzerConfig(padding: 0, minSegmentDuration: 0),
                // A turn rounded beyond the final PCM frame produces an empty segment slice.
                diarizer: try StubDiarizer(slots: [nil, 0])
            ),
            onProgress: { ticks[\.self].append($0) }
        )

        let result = try await pipeline.run()
        #expect(result.tracks.isEmpty == true)
        #expect(ticks[\.self].map(\.overallCompleted) == [1])
        #expect(await counter.value == 0)
    }

    @Test("silent track is omitted from intermediate transcript")
    func emptyTrackDropped() async throws -> Void {
        let speechURL = try TestHelpers.makeTempSineWAV(name: "Speech", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: speechURL) }
        let silenceURL = try TestHelpers.makeTempSineWAV(
            name: "Silence", durationSeconds: 1.0, amplitude: 0.0
        )
        defer { try? FileManager.default.removeItem(at: silenceURL) }

        let transcript = try await TestHelpers.runMockPipeline(tracks: [
            TrackInput(speaker: "Speech", file: speechURL),
            TrackInput(speaker: "Silence", file: silenceURL)
        ])
        #expect(transcript.tracks.count == 1)
        #expect(transcript.tracks.first?.speaker == "Speech")
    }

    @Test("progress callbacks advance monotonically across tracks")
    func progressOrder() async throws -> Void {
        let aliceURL = try TestHelpers.makeTempSineWAV(name: "Alice", durationSeconds: 1.5)
        defer { try? FileManager.default.removeItem(at: aliceURL) }
        let bobURL = try TestHelpers.makeTempSineWAV(name: "Bob", durationSeconds: 1.5)
        defer { try? FileManager.default.removeItem(at: bobURL) }

        let lock = NSLock()
        nonisolated(unsafe) var ticks: [TranscriptionProgress] = []
        let pipeline = TranscribePipeline(
            transcriber: MockTranscriber(),
            config: TestHelpers.mockPipelineConfig(tracks: [
                TrackInput(speaker: "Alice", file: aliceURL),
                TrackInput(speaker: "Bob", file: bobURL)
            ]),
            onProgress: { tick in
                lock.lock()
                ticks.append(tick)
                lock.unlock()
            }
        )
        _ = try await pipeline.run()

        #expect(ticks.isEmpty == false)
        #expect(ticks.last?.overallCompleted == ticks.last?.overallTotal)
        for (a, b) in zip(ticks, ticks.dropFirst()) {
            #expect(b.overallCompleted >= a.overallCompleted)
        }
    }

    @Test("maxConcurrentTranscriptions bounds work across tracks", arguments: [1, 2])
    func maxConcurrent(limit: Int) async throws -> Void {
        let gate = ConcurrentTestGate(batchSize: limit)
        let transcriber = ControlledTranscriber { segment in
            await gate.enter()
            await gate.leave()
            return [.init(text: "bounded", start: segment.start, end: segment.end)]
        }
        let source = try TestHelpers.makeTempSineWAV(name: "bounded-segments")
        defer { try? FileManager.default.removeItem(at: source) }

        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: PipelineConfig(
                tracks: (0 ..< 4).map { TrackInput(speaker: "Speaker \($0)", file: source) },
                transcriptionConfig: TranscriptionConfig(language: "en", prompt: nil),
                maxConcurrentTranscriptions: limit
            )
        )
        let transcript = try await pipeline.run()
        #expect(transcript.tracks.count == 4)
        #expect(transcript.tracks.allSatisfy { $0.segments.count == 1 } == true)
        #expect(await gate.peak == limit)
        #expect(await gate.current == 0)
    }
}
