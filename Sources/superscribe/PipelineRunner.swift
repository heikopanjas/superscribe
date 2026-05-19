import Foundation
import SuperscribeKit

struct PipelineRunResult: Sendable {
    let transcript: IntermediateTranscript
    let duration: TimeInterval
    let backend: Backend
    let model: String
}

struct PipelineRunOptions: Sendable {
    let cliBackend: Backend?
    let cliModel: String?
    let tracks: [TrackInput]
    let transcriptionConfig: @Sendable (String) -> TranscriptionConfig
    let analyzerConfig: AnalyzerConfig
    let useCache: Bool
}

/// Shared transcribe pipeline bootstrap used by `transcribe` and `run`.
enum PipelineRunner {
    struct Dependencies: Sendable {
        var resolveBackendAndModel: @Sendable (Backend?, String?) -> (Backend, String)
        var ensureModelInstalled: @Sendable (String, Backend) async throws -> Void
        var makeTranscriber: @Sendable (Backend, String) throws -> any Transcriber
        var logBackend: @Sendable (Backend, String) -> Void
        var clearProgressLine: @Sendable () -> Void

        static let live = Dependencies(
            resolveBackendAndModel: { cliBackend, cliModel in
                BackendManager.resolveBackendAndModel(
                    cliBackend: cliBackend, cliModel: cliModel
                )
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
        let (backend, model) = dependencies.resolveBackendAndModel(
            options.cliBackend, options.cliModel
        )
        dependencies.logBackend(backend, model)
        try await dependencies.ensureModelInstalled(model, backend)
        let transcriber = try dependencies.makeTranscriber(backend, model)

        let pipelineConfig = PipelineConfig(
            tracks: options.tracks,
            backend: backend,
            transcriptionConfig: options.transcriptionConfig(model),
            analyzerConfig: options.analyzerConfig,
            session: nil
        )

        let audioCache: ConvertedAudioCache? = options.useCache ? ConvertedAudioCache() : nil
        let conversionReporter = ConversionProgressReporter()

        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: pipelineConfig,
            audioCache: audioCache,
            onProgress: makeProgressHandler(),
            onConversionProgress: conversionReporter.handler()
        )

        let start = Date()
        let transcript = try await pipeline.run()
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
