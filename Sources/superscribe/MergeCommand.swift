import ArgumentParser
import Foundation
import SuperscribeKit

struct MergeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "merge",
        abstract: "Merge an intermediate transcript into a formatted output."
    )

    @Argument(help: "Path to the intermediate `.superscribe.json` file.")
    var intermediateFile: String

    @OptionGroup var options: MergeOptions

    mutating func run() async throws -> Void {
        let data = try Data(contentsOf: URL(fileURLWithPath: self.intermediateFile))
        let transcript = try IntermediateTranscript.jsonDecoder().decode(
            IntermediateTranscript.self, from: data
        )

        let output = try Self.renderMerged(transcript, options: self.options)

        if let path = self.options.mergeOutput {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
        }
        else {
            print(output, terminator: "")
        }
    }

    static func renderMerged(
        _ transcript: IntermediateTranscript,
        options: MergeOptions
    ) throws -> String {
        return try TranscriptRenderer.render(transcript, configuration: options.renderConfiguration)
    }
}
