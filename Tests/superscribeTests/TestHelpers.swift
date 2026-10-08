import AVFoundation
import CoreML
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Temp directories

enum TestHelpers {
    /// Avoids recursively expanding #require inside another #require on Swift 6.4.
    static func requireValue<Value>(_ value: Value?, sourceLocation: SourceLocation = #_sourceLocation()) throws -> Value {
        return try #require(value, sourceLocation: sourceLocation)
    }

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
        let dir = try Self.makeTempDir(prefix: prefix)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// Async variant for tests that await inside the workspace.
    static func withTempDirectory<T>(
        prefix: String = "superscribe-tests",
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let dir = try Self.makeTempDir(prefix: prefix)
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
        return try Self.makeTempSineWAV(
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
        let format = (try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)))
        let buffer = (try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)))
        buffer.frameLength = frameCount
        let freq: Float = 440.0
        for ch in 0 ..< Int(channels) {
            let floats = (try #require(buffer.floatChannelData))[ch]
            for i in 0 ..< Int(frameCount) {
                floats[i] = sinf(2.0 * .pi * freq * Float(i) / Float(sampleRate)) * amplitude
            }
        }
        return try Self.writeWAV(buffer: buffer, name: name)
    }

    static func writeWAV(buffer: AVAudioPCMBuffer, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).wav")
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
        }
        return url
    }

    static func makeTempPCM(samples: [Float], name: String) throws -> URL {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = try #require(buffer.floatChannelData?[0])
        for (index, sample) in samples.enumerated() { channel[index] = sample }
        return try Self.writeWAV(buffer: buffer, name: name)
    }

    /// 16 kHz mono Float32 WAV matching `.asr16kMono` for AudioPreparer fast path.
    static func makeTemp16kMonoFloatWAV(name: String, durationSeconds: Double = 0.5) throws -> URL {
        return try Self.makeTempSineWAV(
            name: name,
            durationSeconds: durationSeconds,
            sampleRate: 16_000,
            channels: 1,
            amplitude: 0.25
        )
    }

    /// Minimal repository layout; no fixture model is used for inference.
    static let parakeetFiles = ["Preprocessor.mlmodelc/model.mil", "Encoder.mlmodelc/model.mil", "Decoder.mlmodelc/model.mil", "JointDecisionv3.mlmodelc/model.mil", "parakeet_vocab.json"]

    static func makeParakeetInstallation(at root: URL) throws -> Void {
        for name in Self.parakeetFiles {
            let file = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("bin".utf8).write(to: file)
        }
    }

    /// Fetches the repository listing and downloads every file at its repository path (no model-specific selection).
    static func downloadRepository(
        model: RemoteModelInfo, backend: Backend?, into staging: URL, session: URLSession, onProgress: @Sendable @escaping (SuperscribeKit.DownloadProgress) -> Void
    ) async throws -> Void {
        let siblings = try await HuggingFaceHub.repoInfo(repoId: model.repoId, session: session).siblings
        let files = siblings.map { ModelDownloadFile(rfilename: $0.rfilename, relativePath: $0.rfilename, expectedSize: $0.size) }
        try await ModelDownloader.download(files: files, model: model, backend: backend, into: staging, session: session, onProgress: onProgress)
    }

    /// Complete diarizer layout (bundle, silence embedding, weights marker) without a loadable model.
    static func makeDiarizerInstallation(at root: URL) throws -> Void {
        let bundle = root.appendingPathComponent(DiarizerModel.config.modelFileName)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("bin".utf8).write(to: bundle.appendingPathComponent("coremldata.bin"))
        try Data("emb".utf8).write(to: root.appendingPathComponent("learnable_sil_emb.bin"))
        try DiarizerModel.writeMarker(in: root)
    }

    /// Builds storage-only ASR stubs from our tiny scalar regression fixture.
    static func makeStubAsrModels(version: AsrModelVersion = .v3) throws -> AsrModels {
        let source = try #require(Bundle.module.url(forResource: "Scalar", withExtension: "mlmodel", subdirectory: "Fixtures"))
        let compiled = try MLModel.compileModel(at: source)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let stubModel = try MLModel(contentsOf: compiled)
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

    /// Runs `body` with an isolated models root, passing its existing Parakeet and Whisper directories.
    static func withIsolatedModelCaches<T>(
        _ body: (URL, URL) async throws -> T
    ) async throws -> T {
        let modelsRoot = try Self.makeTempDir(prefix: "models")
        let prior = SuperscribePaths.overrideModelsDirectory
        SuperscribePaths.overrideModelsDirectory = nil
        defer {
            SuperscribePaths.overrideModelsDirectory = prior
            try? FileManager.default.removeItem(at: modelsRoot)
        }
        return try await SuperscribePaths.$taskModelsDirectory.withValue(modelsRoot) {
            let parakeetRoot = SuperscribePaths.parakeetModelsDirectory()
            let whisperRoot = SuperscribePaths.whisperModelsDirectory()
            for root in [parakeetRoot, whisperRoot] { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            return try await body(parakeetRoot, whisperRoot)
        }
    }

    // MARK: - Mock pipeline

    static func mockPipelineConfig(
        tracks: [TrackInput],
        backend: Backend = .parakeet,
        model: String = "test",
        language: String? = "en"
    ) -> PipelineConfig {
        return PipelineConfig(
            tracks: tracks,
            backend: backend,
            transcriptionConfig: TranscriptionConfig(
                language: language, prompt: nil
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
            transcriber: MockTranscriber(modelId: model),
            config: Self.mockPipelineConfig(
                tracks: tracks, backend: backend, model: model, language: language
            )
        )
        return try await pipeline.run()
    }
}
