import ArgumentParser
import Foundation
import SuperscribeKit

/// Options shared by the `transcribe` and `run` subcommands.
struct TranscribeOptions: ParsableArguments {
    @Option(
        name: .long,
        parsing: .singleValue,
        help: ArgumentHelp("Speaker track in the form `name=path`.", valueName: "name=path")
    )
    var track: [TrackSpec] = []

    @Option(name: .long, help: "Transcription backend (parakeet, whisper.cpp, appleSpeech). Uses configured default if omitted.")
    var backend: Backend?

    @Option(
        name: .long,
        help:
            "Model variant. Parakeet: v2, v3, tdt-ctc-110m, tdt-ja. Whisper: large-v3-turbo, base, medium-q5_0, etc. Apple Speech: en-US, de-DE, etc. (run `model --list --remote --backend <name>` for all). Uses configured default if omitted."
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

    mutating func validate() throws -> Void { try self.analyzerConfig.validate() }
}

// MARK: - Convenience bridges from CLI options to library types

extension TranscribeOptions {
    var trackInputs: [TrackInput] {
        return self.track.map { TrackInput(speaker: $0.speaker, file: URL(fileURLWithPath: $0.path)) }
    }

    var transcriptionConfig: TranscriptionConfig {
        return TranscriptionConfig(language: self.language, prompt: self.prompt)
    }

    var analyzerConfig: AnalyzerConfig {
        return AnalyzerConfig(
            silenceThresholdDB: self.silenceThreshold,
            minSilenceDuration: self.minSilence,
            padding: self.padding
        )
    }
}
