import ArgumentParser
import Foundation

extension Backend: ExpressibleByArgument {}
extension OverlapPolicy: ExpressibleByArgument {}
extension OutputFormat: ExpressibleByArgument {}

/// Parses a `name=path` track specification into its components.
struct TrackSpec: ExpressibleByArgument {
    let speaker: String
    let path: String

    init?(argument: String) {
        guard let separator = argument.firstIndex(of: "=") else { return nil }
        let speaker = String(argument[..<separator]).trimmingCharacters(in: .whitespaces)
        let path = String(argument[argument.index(after: separator)...]).trimmingCharacters(
            in: .whitespaces)
        guard !speaker.isEmpty, !path.isEmpty else { return nil }
        self.speaker = speaker
        self.path = path
    }
}

/// Options shared by the `transcribe` and `run` subcommands.
struct TranscribeOptions: ParsableArguments {
    @Option(
        name: .long,
        parsing: .singleValue,
        help: ArgumentHelp("Speaker track in the form `name=path`.", valueName: "name=path")
    )
    var track: [TrackSpec] = []

    @Option(name: .long, help: "Transcription backend.")
    var backend: Backend = .auto

    @Option(name: .long, help: "Whisper model size.")
    var model: String = "large-v3-turbo"

    @Option(name: .long, help: "Language code (e.g. en, de). Auto-detect if omitted.")
    var language: String?

    @Option(name: .long, help: "Context hint to bias recognition.")
    var prompt: String?

    @Option(name: .long, help: "Intermediate file path.")
    var output: String = "transcript.superscribe.json"

    @Option(name: .long, help: "Silence threshold in dB.")
    var silenceThreshold: Double = -40.0

    @Option(name: .long, help: "Minimum silence gap to split (seconds).")
    var minSilence: TimeInterval = 0.5

    @Option(name: .long, help: "Speech segment padding (seconds).")
    var padding: TimeInterval = 0.15

    @Flag(name: .long, help: "Show progress and segment details.")
    var verbose: Bool = false
}

/// Options shared by the `merge` and `run` subcommands.
struct MergeOptions: ParsableArguments {
    @Option(name: .long, help: "Output format.")
    var format: OutputFormat = .vtt

    @Option(name: .long, help: "Output file (default: stdout).")
    var mergeOutput: String?

    @Option(name: .long, help: "How to handle overlapping speech.")
    var overlapPolicy: OverlapPolicy = .preserve

    @Option(name: .long, help: "Wrap long cues at this many characters.")
    var maxLineLength: Int?

    @Option(name: .long, help: "Split cues longer than this (seconds).")
    var maxCueDuration: TimeInterval?

    @Option(name: .long, help: "Insert paragraph breaks for pauses longer than this (seconds).")
    var gapThreshold: TimeInterval = 3.0

    @Flag(name: .long, help: "Keep word-level timestamps in the output.")
    var includeWords: Bool = false
}
