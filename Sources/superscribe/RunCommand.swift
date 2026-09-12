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

    mutating func run() async throws -> Void {
        let opts = self.transcribeOptions
        let result = try await PipelineRunner.run(
            options: PipelineRunOptions(
                cliBackend: opts.backend,
                cliModel: opts.model,
                tracks: opts.trackInputs,
                transcriptionConfig: opts.transcriptionConfig,
                analyzerConfig: opts.analyzerConfig,
                useCache: opts.noCache == false
            )
        )

        printTranscribeSummary(transcript: result.transcript, duration: result.duration)

        if self.keepIntermediate == true {
            let outputPath = defaultIntermediateOutputPath(
                backend: result.backend,
                explicitOutput: self.transcribeOptions.output
            )
            try saveIntermediateTranscript(result.transcript, to: outputPath)
        }

        let output = try MergeCommand.renderMerged(result.transcript, options: self.mergeOptions)

        if let path = self.mergeOptions.mergeOutput {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
        }
        else {
            print(output, terminator: "")
        }
    }
}
