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
        let result = try await PipelineRunner.run(options: self.transcribeOptions.pipelineRunOptions(tracks: self.transcribeOptions.trackInputs))

        printTranscribeSummary(transcript: result.transcript, duration: result.duration)

        if self.keepIntermediate == true {
            let outputPath = defaultIntermediateOutputPath(
                backend: result.backend,
                explicitOutput: self.transcribeOptions.output
            )
            try saveIntermediateTranscript(result.transcript, to: outputPath)
        }

        let output = try MergeCommand.renderMerged(result.transcript, options: self.mergeOptions)

        try writeRenderedOutput(output, to: self.mergeOptions.mergeOutput)
    }
}
