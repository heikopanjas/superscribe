import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Mock backend

/// A deterministic transcriber for testing: returns one word per segment
/// with text "mock-word".
struct MockTranscriber: Transcriber {
    static var isAvailable: Bool { true }

    var capabilities: BackendCapabilities {
        BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Mock",
            defaultModelId: "mock"
        )
    }

    func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        let word = TimedWord(
            text: "mock-word",
            start: segment.start,
            end: segment.end
        )
        return SegmentTranscription(segment: segment, words: [word])
    }
}

// MARK: - Pipeline tests

@Suite("Pipeline")
struct PipelineTests {
    /// Writes a short sine-wave WAV to a temp file and returns its URL.
    private func makeTempAudio(name: String, durationSeconds: Double = 1.0) throws -> URL {
        let sampleRate: Double = 48_000
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let floats = buffer.floatChannelData![0]
        let freq: Float = 440.0
        for i in 0 ..< Int(frameCount) {
            floats[i] = sinf(2.0 * .pi * freq * Float(i) / Float(sampleRate)) * 0.5
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    @Test("pipeline produces intermediate transcript from two tracks")
    func twoTracks() async throws {
        let aliceURL = try makeTempAudio(name: "Alice", durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: aliceURL) }
        let bobURL = try makeTempAudio(name: "Bob", durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: bobURL) }

        let config = PipelineConfig(
            tracks: [
                TrackInput(speaker: "Alice", file: aliceURL),
                TrackInput(speaker: "Bob", file: bobURL)
            ],
            transcriptionConfig: TranscriptionConfig(
                language: "en", model: "test", prompt: nil
            ),
            analyzerConfig: AnalyzerConfig()
        )

        let pipeline = TranscribePipeline(
            transcriber: MockTranscriber(),
            config: config
        )
        let transcript = try await pipeline.run()

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
        let url = try makeTempAudio(name: "Solo", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = PipelineConfig(
            tracks: [TrackInput(speaker: "Solo", file: url)],
            transcriptionConfig: TranscriptionConfig(
                language: nil, model: "test", prompt: nil
            )
        )

        let pipeline = TranscribePipeline(
            transcriber: MockTranscriber(),
            config: config
        )
        let original = try await pipeline.run()

        let data = try IntermediateTranscript.jsonEncoder().encode(original)
        let decoded = try IntermediateTranscript.jsonDecoder().decode(
            IntermediateTranscript.self, from: data
        )

        #expect(decoded.version == original.version)
        #expect(decoded.tracks.count == original.tracks.count)
        #expect(decoded.tracks.first?.speaker == "Solo")
        #expect(decoded.tracks.first?.segments.count == original.tracks.first?.segments.count)
    }
}

// MARK: - End-to-end merge test

@Suite("EndToEnd")
struct EndToEndTests {
    @Test("pipeline + merger produces VTT with both speakers")
    func pipelineToVTT() async throws {
        let sampleRate: Double = 48_000
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        func writeAudio(name: String, seconds: Double) throws -> URL {
            let frameCount = AVAudioFrameCount(sampleRate * seconds)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            let floats = buffer.floatChannelData![0]
            for i in 0 ..< Int(frameCount) {
                floats[i] = sinf(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate)) * 0.5
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name)-\(UUID().uuidString).wav")
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }

        let aliceURL = try writeAudio(name: "Alice", seconds: 1.0)
        defer { try? FileManager.default.removeItem(at: aliceURL) }
        let bobURL = try writeAudio(name: "Bob", seconds: 1.0)
        defer { try? FileManager.default.removeItem(at: bobURL) }

        // Transcribe
        let pipelineConfig = PipelineConfig(
            tracks: [
                TrackInput(speaker: "Alice", file: aliceURL),
                TrackInput(speaker: "Bob", file: bobURL)
            ],
            transcriptionConfig: TranscriptionConfig(
                language: "en", model: "test", prompt: nil
            )
        )
        let pipeline = TranscribePipeline(
            transcriber: MockTranscriber(),
            config: pipelineConfig
        )
        let transcript = try await pipeline.run()

        // Merge + format
        let merger = Merger()
        let merged = merger.merge(transcript)
        let vtt = VTTFormatter(includeWords: false).render(merged)

        #expect(vtt.hasPrefix("WEBVTT\n"))
        #expect(vtt.contains("<v Alice>"))
        #expect(vtt.contains("<v Bob>"))
    }
}
