import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Pipeline")
struct PipelineTests {
    @Test("pipeline produces intermediate transcript from two tracks")
    func twoTracks() async throws {
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
    func jsonRoundTrip() async throws {
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
    func backendMetadata() async throws {
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
    func emptySegmentSkipsTranscriber() async throws {
        let counter = TranscribeCallCounter()
        let transcriber = CountingTranscriber(counter: counter)
        let preparer = AudioPreparer(for: transcriber.capabilities)
        let samples = Array(repeating: Float(0.1), count: 16_000)
        let segments = [SpeechSegment(start: 0.5, end: 0.5)]

        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: PipelineConfig(
                tracks: [TrackInput(speaker: "Solo", file: URL(fileURLWithPath: "/tmp/x.wav"))],
                backend: .parakeet,
                transcriptionConfig: TranscriptionConfig(language: "en", model: "test", prompt: nil)
            )
        )

        let results = try await pipeline.transcribeSegments(
            segments,
            allSamples: samples,
            preparer: preparer
        )
        #expect(results.isEmpty == true)
        #expect(await counter.count == 0)
    }

    @Test("silent track is omitted from intermediate transcript")
    func emptyTrackDropped() async throws {
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
    func progressOrder() async throws {
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

    @Test("maxConcurrentTranscriptions bounds parallel segment work")
    func maxConcurrent() async throws {
        let depth = ConcurrencyDepthTracker()
        let transcriber = SlowTranscriber(depth: depth)
        let preparer = AudioPreparer(for: transcriber.capabilities)
        let samples = Array(repeating: Float(0.1), count: 64_000)
        let segments = (0 ..< 4).map {
            SpeechSegment(start: Double($0) * 0.5, end: Double($0) * 0.5 + 0.4)
        }

        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: PipelineConfig(
                tracks: [TrackInput(speaker: "Solo", file: URL(fileURLWithPath: "/tmp/x.wav"))],
                transcriptionConfig: TranscriptionConfig(language: "en", model: "test", prompt: nil),
                maxConcurrentTranscriptions: 1
            )
        )
        _ = try await pipeline.transcribeSegments(
            segments,
            allSamples: samples,
            preparer: preparer
        )
        #expect(await depth.peak == 1)
    }
}

private struct CountingTranscriber: Transcriber {
    let counter: TranscribeCallCounter

    var capabilities: BackendCapabilities {
        BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Counter",
            defaultModelId: "counter"
        )
    }

    func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        await counter.increment()
        return SegmentTranscription(
            segment: segment,
            words: [TimedWord(text: "x", start: segment.start, end: segment.end)]
        )
    }
}

private actor TranscribeCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor ConcurrencyDepthTracker {
    private(set) var peak = 0
    private var inFlight = 0

    func entered() {
        inFlight += 1
        if inFlight > peak { peak = inFlight }
    }

    func exited() {
        inFlight -= 1
    }
}

private struct SlowTranscriber: Transcriber {
    let depth: ConcurrencyDepthTracker

    var capabilities: BackendCapabilities {
        BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Slow",
            defaultModelId: "slow"
        )
    }

    func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        await depth.entered()
        try await Task.sleep(for: .milliseconds(50))
        await depth.exited()
        return SegmentTranscription(
            segment: segment,
            words: [TimedWord(text: "slow", start: segment.start, end: segment.end)]
        )
    }
}

// MARK: - End-to-end merge test

@Suite("EndToEnd")
struct EndToEndTests {
    @Test("pipeline + merger produces VTT with both speakers")
    func pipelineToVTT() async throws {
        let aliceURL = try TestHelpers.makeTempSineWAV(name: "Alice", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: aliceURL) }
        let bobURL = try TestHelpers.makeTempSineWAV(name: "Bob", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: bobURL) }

        let transcript = try await TestHelpers.runMockPipeline(tracks: [
            TrackInput(speaker: "Alice", file: aliceURL),
            TrackInput(speaker: "Bob", file: bobURL)
        ])

        let merger = Merger()
        let merged = merger.merge(transcript)
        let vtt = VTTFormatter(includeWords: false).render(merged)

        #expect(vtt.hasPrefix("WEBVTT\n"))
        #expect(vtt.contains("<v Alice>"))
        #expect(vtt.contains("<v Bob>"))
    }
}
