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
        let opts = transcribeOptions
        let result = try await PipelineRunner.run(
            options: PipelineRunOptions(
                cliBackend: opts.backend,
                cliModel: opts.model,
                tracks: opts.trackInputs,
                transcriptionConfig: { model in opts.transcriptionConfig(model: model) },
                analyzerConfig: opts.analyzerConfig,
                useCache: opts.noCache == false
            )
        )

        printTranscribeSummary(transcript: result.transcript, duration: result.duration)

        if keepIntermediate == true {
            let outputPath = defaultIntermediateOutputPath(
                backend: result.backend,
                explicitOutput: transcribeOptions.output
            )
            try saveIntermediateTranscript(result.transcript, to: outputPath)
        }

        let output = MergeCommand.renderMerged(result.transcript, options: mergeOptions)

        if let path = mergeOptions.mergeOutput {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
        }
        else {
            print(output, terminator: "")
        }
    }
}
