import AVFoundation
import CoreML
import FluidAudio
import Foundation

@testable import SuperscribeKit

// MARK: - Temp directories

enum TestHelpers {
    /// Creates a unique temporary directory; caller must remove it.
    static func makeTempDir(prefix: String = "superscribe-tests") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Runs `body` inside a temporary directory that is removed on exit.
    static func withTempDirectory<T>(
        prefix: String = "superscribe-tests",
        _ body: (URL) throws -> T
    ) throws -> T {
        let dir = try makeTempDir(prefix: prefix)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// Async variant for tests that await inside the workspace.
    static func withTempDirectory<T>(
        prefix: String = "superscribe-tests",
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let dir = try makeTempDir(prefix: prefix)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    // MARK: - Audio fixtures

    /// Writes a short sine-wave WAV to a temp file and returns its URL.
    static func makeTempSineWAV(
        name: String,
        durationSeconds: Double = 1.0,
        sampleRate: Double = 48_000,
        amplitude: Float = 0.5
    ) throws -> URL {
        try makeTempSineWAV(
            name: name,
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            channels: 1,
            amplitude: amplitude
        )
    }

    /// Writes a sine-wave WAV with explicit channel count.
    static func makeTempSineWAV(
        name: String,
        durationSeconds: Double,
        sampleRate: Double,
        channels: AVAudioChannelCount,
        amplitude: Float = 0.5
    ) throws -> URL {
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let freq: Float = 440.0
        for ch in 0 ..< Int(channels) {
            let floats = buffer.floatChannelData![ch]
            for i in 0 ..< Int(frameCount) {
                floats[i] = sinf(2.0 * .pi * freq * Float(i) / Float(sampleRate)) * amplitude
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    /// 16 kHz mono Float32 WAV matching `.asr16kMono` for AudioPreparer fast path.
    static func makeTemp16kMonoFloatWAV(name: String, durationSeconds: Double = 0.5) throws -> URL {
        try makeTempSineWAV(
            name: name,
            durationSeconds: durationSeconds,
            sampleRate: 16_000,
            channels: 1,
            amplitude: 0.25
        )
    }

    /// Builds `AsrModels` with a bundled macOS Core ML model (no Hugging Face download).
    /// `AsrManager.loadModels` only stores references; weights are not executed in these tests.
    static func makeStubAsrModels(version: AsrModelVersion = .v3) throws -> AsrModels {
        let modelURL = URL(
            fileURLWithPath: "/System/Library/CoreServices/MapsSuggestionsTransportModePrediction.mlmodelc"
        )
        let stubModel = try MLModel(contentsOf: modelURL)
        let config = MLModelConfiguration()
        return AsrModels(
            encoder: stubModel,
            preprocessor: stubModel,
            decoder: stubModel,
            joint: stubModel,
            configuration: config,
            vocabulary: [0: "▁a"],
            version: version
        )
    }

    /// Runs `body` with isolated Parakeet and Whisper cache directory overrides.
    static func withIsolatedModelCaches<T>(
        _ body: (URL, URL) async throws -> T
    ) async throws -> T {
        let parakeetRoot = try makeTempDir(prefix: "pk-cache")
        let whisperRoot = try makeTempDir(prefix: "wh-cache")
        let priorParakeet = SuperscribePaths.overrideFluidAudioModelsDirectory
        let priorWhisper = SuperscribePaths.overrideWhisperModelCacheDirectory
        SuperscribePaths.overrideFluidAudioModelsDirectory = nil
        SuperscribePaths.overrideWhisperModelCacheDirectory = nil
        defer {
            SuperscribePaths.overrideFluidAudioModelsDirectory = priorParakeet
            SuperscribePaths.overrideWhisperModelCacheDirectory = priorWhisper
            try? FileManager.default.removeItem(at: parakeetRoot)
            try? FileManager.default.removeItem(at: whisperRoot)
        }
        return try await SuperscribePaths.$taskWhisperModelCacheDirectory.withValue(whisperRoot) {
            try await SuperscribePaths.$taskFluidAudioModelsDirectory.withValue(parakeetRoot) {
                try await body(parakeetRoot, whisperRoot)
            }
        }
    }

    // MARK: - Mock pipeline

    static func mockPipelineConfig(
        tracks: [TrackInput],
        backend: Backend = .parakeet,
        model: String = "test",
        language: String? = "en"
    ) -> PipelineConfig {
        PipelineConfig(
            tracks: tracks,
            backend: backend,
            transcriptionConfig: TranscriptionConfig(
                language: language, model: model, prompt: nil
            ),
            analyzerConfig: AnalyzerConfig()
        )
    }

    static func runMockPipeline(
        tracks: [TrackInput],
        backend: Backend = .parakeet,
        model: String = "test",
        language: String? = "en"
    ) async throws -> IntermediateTranscript {
        let pipeline = TranscribePipeline(
            transcriber: MockTranscriber(),
            config: mockPipelineConfig(
                tracks: tracks, backend: backend, model: model, language: language
            )
        )
        return try await pipeline.run()
    }
}

// MARK: - Mock transcriber

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
