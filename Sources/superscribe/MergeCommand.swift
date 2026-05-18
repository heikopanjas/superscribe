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

    mutating func run() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: intermediateFile))
        let transcript = try IntermediateTranscript.jsonDecoder().decode(
            IntermediateTranscript.self, from: data
        )

        let output = Self.renderMerged(transcript, options: options)

        if let path = options.mergeOutput {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
        }
        else {
            print(output, terminator: "")
        }
    }

    static func renderMerged(
        _ transcript: IntermediateTranscript,
        options: MergeOptions
    ) -> String {
        let merger = Merger(
            config: MergerConfig(
                overlapPolicy: options.overlapPolicy,
                gapThreshold: options.gapThreshold,
                maxCueDuration: options.maxCueDuration
            )
        )
        let merged = merger.merge(transcript)

        switch options.format {
            case .vtt:
                return VTTFormatter(includeWords: options.includeWords).render(merged)
            case .srt, .json, .txt:
                fatalError("Output format `\(options.format.rawValue)` is not yet implemented")
        }
    }
}
