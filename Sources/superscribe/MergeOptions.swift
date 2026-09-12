import ArgumentParser
import Foundation
import SuperscribeKit

/// Options shared by the `merge` and `run` subcommands.
struct MergeOptions: ParsableArguments {
    @Option(name: .long, help: "Output format.")
    var format: OutputFormat = .vtt

    @Option(name: .long, help: "Output file (default: stdout).")
    var mergeOutput: String?

    @Option(name: .long, help: "How to handle overlapping speech.")
    var overlapPolicy: OverlapPolicy?

    @Option(name: .long, help: "Wrap long cues at this many characters.")
    var maxLineLength: Int?

    @Option(name: .long, help: "Split cues longer than this (seconds).")
    var maxCueDuration: TimeInterval?

    @Option(name: .long, help: "Insert paragraph breaks for pauses longer than this (seconds).")
    var gapThreshold: TimeInterval = 3.0

    @Flag(name: .long, help: "Keep word-level timestamps in the output.")
    var includeWords: Bool = false

    var renderConfiguration: RenderConfiguration {
        return RenderConfiguration(
            format: self.format, overlapPolicy: self.overlapPolicy, gapThreshold: self.gapThreshold, maxCueDuration: self.maxCueDuration, maxLineLength: self.maxLineLength,
            includeWords: self.includeWords)
    }

    mutating func validate() throws -> Void { try self.renderConfiguration.validate() }

}
