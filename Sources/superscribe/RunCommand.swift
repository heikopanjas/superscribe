import ArgumentParser
import Foundation
import SuperscribeKit

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Transcribe and merge in a single pass."
    )

    @OptionGroup var transcribeOptions: TranscribeOptions
    @OptionGroup var mergeOptions: MergeOptions

    @Flag(name: .long, help: "Save the intermediate file (default: discard).")
    var keepIntermediate: Bool = false

    mutating func run() async throws {
        let (backend, model) = BackendManager.resolveBackendAndModel(
            cliBackend: transcribeOptions.backend, cliModel: transcribeOptions.model
        )
        FileHandle.standardError.write(
            Data("Using backend: \(backend.rawValue), model: \(model)\n".utf8)
        )
        try await ModelManager.ensureModelInstalled(model, backend: backend)
        let transcriber = try BackendManager.makeTranscriber(backend: backend, model: model)

        let pipelineConfig = PipelineConfig(
            tracks: transcribeOptions.trackInputs,
            transcriptionConfig: transcribeOptions.transcriptionConfig(model: model),
            analyzerConfig: transcribeOptions.analyzerConfig,
            session: nil
        )

        let audioCache: ConvertedAudioCache? = transcribeOptions.noCache ? nil : ConvertedAudioCache()
        let conversionReporter = ConversionProgressReporter()

        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: pipelineConfig,
            audioCache: audioCache,
            onProgress: makeProgressHandler(),
            onConversionProgress: conversionReporter.handler()
        )

        let transcribeStart = Date()
        let transcript = try await pipeline.run()
        let transcribeDuration = Date().timeIntervalSince(transcribeStart)

        // Clear progress line.
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))

        let segCount = transcript.tracks.reduce(0) { $0 + $1.segments.count }
        let trackCount = transcript.tracks.count
        FileHandle.standardError.write(
            Data("Transcribed \(segCount) segments from \(trackCount) track(s) in \(formatDuration(transcribeDuration))\n".utf8)
        )

        if keepIntermediate == true {
            let data = try IntermediateTranscript.jsonEncoder().encode(transcript)
            let outputPath =
                transcribeOptions.output.isEmpty
                ? "transcript.superscribe.\(backend.rawValue).json"
                : transcribeOptions.output
            let outputURL = URL(fileURLWithPath: outputPath)
            try data.write(to: outputURL)
        }

        let output = MergeCommand.renderMerged(transcript, options: mergeOptions)

        if let path = mergeOptions.mergeOutput {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
        }
        else {
            print(output, terminator: "")
        }
    }
}
