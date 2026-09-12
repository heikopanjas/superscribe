import Foundation
import SuperscribeKit

/// Shared transcribe pipeline bootstrap used by `transcribe` and `run`.
enum PipelineRunner {
    struct Dependencies: Sendable {
        var resolveBackendAndModel: @Sendable (Backend?, String?) async throws -> (Backend, String)
        var ensureModelInstalled: @Sendable (String, Backend) async throws -> Void
        var makeTranscriber: @Sendable (Backend, String) throws -> any Transcriber
        var logBackend: @Sendable (Backend, String) -> Void
        var clearProgressLine: @Sendable () -> Void

        static let live = Dependencies(
            resolveBackendAndModel: { cliBackend, cliModel in
                let config = try UserConfig.load()
                let backend = try BackendManager.resolveBackend(cliBackend: cliBackend, config: config)
                let model = try await backend.resolveModelId(cliModel ?? config.defaultModel(for: backend))
                return (backend, model)
            },
            ensureModelInstalled: ModelManager.ensureModelInstalled,
            makeTranscriber: BackendManager.makeTranscriber,
            logBackend: { backend, model in
                FileHandle.standardError.write(
                    Data("Using backend: \(backend.rawValue), model: \(model)\n".utf8)
                )
            },
            clearProgressLine: {
                FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
            }
        )
    }

    static func run(
        options: PipelineRunOptions,
        dependencies: Dependencies = .live
    ) async throws -> PipelineRunResult {
        try TrackInput.validate(options.tracks)
        try options.analyzerConfig.validate()
        let (backend, model) = try await dependencies.resolveBackendAndModel(
            options.cliBackend, options.cliModel
        )
        dependencies.logBackend(backend, model)
        let configuration = options.transcriptionConfig
        try configuration.validate()
        let transcriber = try dependencies.makeTranscriber(backend, model)
        try await dependencies.ensureModelInstalled(model, backend)

        let pipelineConfig = PipelineConfig(
            tracks: options.tracks,
            backend: backend,
            transcriptionConfig: configuration,
            analyzerConfig: options.analyzerConfig,
            session: nil
        )

        let audioCache: ConvertedAudioCache? = options.useCache ? ConvertedAudioCache() : nil
        let reporter = ProgressReporter()

        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: pipelineConfig,
            audioCache: audioCache,
            onProgress: reporter.transcription,
            onConversionProgress: reporter.conversion
        )

        let start = Date()
        let transcript: IntermediateTranscript
        do {
            transcript = try await pipeline.run()
            await reporter.finish()
        }
        catch {
            await reporter.finish()
            throw error
        }
        let duration = Date().timeIntervalSince(start)
        dependencies.clearProgressLine()

        return PipelineRunResult(
            transcript: transcript,
            duration: duration,
            backend: backend,
            model: model
        )
    }
}
