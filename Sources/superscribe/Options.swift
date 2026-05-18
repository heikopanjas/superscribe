import ArgumentParser
import Foundation
import SuperscribeKit

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
        guard speaker.isEmpty == false, path.isEmpty == false else { return nil }
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

    @Option(name: .long, help: "Transcription backend (parakeet, whisper.cpp). Uses configured default if omitted.")
    var backend: Backend?

    @Option(
        name: .long,
        help:
            "Model variant. Parakeet: v2, v3, tdt-ctc-110m, tdt-ja. Whisper: large-v3-turbo, base, medium-q5_0, etc. (run `model --list --backend whisper.cpp` for all). Uses configured default if omitted."
    )
    var model: String?

    @Option(name: .long, help: "Language code (e.g. en, de). Auto-detect if omitted.")
    var language: String?

    @Option(name: .long, help: "Context hint to bias recognition.")
    var prompt: String?

    @Option(name: .long, help: "Intermediate file path (default: transcript.superscribe.<backend>.json).")
    var output: String = ""

    @Option(name: .long, help: "Silence threshold in dB.")
    var silenceThreshold: Double = -40.0

    @Option(name: .long, help: "Minimum silence gap to split (seconds).")
    var minSilence: TimeInterval = 0.5

    @Option(name: .long, help: "Speech segment padding (seconds).")
    var padding: TimeInterval = 0.15

    @Flag(name: .long, help: "Show progress and segment details.")
    var verbose: Bool = false

    @Flag(name: .long, help: "Skip the converted-audio cache (always re-convert from the source file).")
    var noCache: Bool = false
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

// MARK: - Convenience bridges from CLI options to library types

extension TranscribeOptions {
    var trackInputs: [TrackInput] {
        track.map { TrackInput(speaker: $0.speaker, file: URL(fileURLWithPath: $0.path)) }
    }

    func transcriptionConfig(model: String) -> TranscriptionConfig {
        TranscriptionConfig(language: language, model: model, prompt: prompt)
    }

    var analyzerConfig: AnalyzerConfig {
        AnalyzerConfig(
            silenceThresholdDB: silenceThreshold,
            minSilenceDuration: minSilence,
            padding: padding
        )
    }
}
