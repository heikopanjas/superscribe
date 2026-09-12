import ArgumentParser
import Foundation
import SuperscribeKit

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Detect speech in each track and produce an intermediate transcript."
    )

    @OptionGroup var options: TranscribeOptions

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Scan a directory for audio files and write tracks.superscribe.json. Cannot be combined with --track or --input.",
            valueName: "directory"
        )
    )
    var createInput: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Load track mapping from a file created with --create-input. Cannot be combined with --track.",
            valueName: "file"
        )
    )
    var input: String?

    mutating func validate() throws -> Void {
        let hasTrack = !self.options.track.isEmpty
        if self.createInput != nil {
            if hasTrack == true { throw ValidationError("--create-input may not be combined with --track.") }
            if self.input != nil { throw ValidationError("--create-input may not be combined with --input.") }
        }
        if self.input != nil, hasTrack == true {
            throw ValidationError("--input may not be combined with --track.")
        }
    }

    mutating func run() async throws -> Void {
        if let dir = self.createInput {
            try self.runCreateInput(directory: dir)
            return
        }

        let resolvedTracks: [TrackInput]
        if let inputFile = self.input {
            resolvedTracks = try TrackMappingLoader.load(from: URL(fileURLWithPath: inputFile), relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        }
        else {
            resolvedTracks = self.options.trackInputs
        }

        let opts = self.options
        let result = try await PipelineRunner.run(
            options: PipelineRunOptions(
                cliBackend: opts.backend,
                cliModel: opts.model,
                tracks: resolvedTracks,
                transcriptionConfig: opts.transcriptionConfig,
                analyzerConfig: opts.analyzerConfig,
                useCache: opts.noCache == false
            )
        )

        let outputPath = defaultIntermediateOutputPath(
            backend: result.backend,
            explicitOutput: self.options.output
        )
        try saveIntermediateTranscript(result.transcript, to: outputPath)
        printTranscribeSummary(transcript: result.transcript, duration: result.duration)
        FileHandle.standardError.write(Data("Output: \(outputPath)\n".utf8))
    }

    // MARK: - --create-input

    private func runCreateInput(directory: String) throws -> Void {
        let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let tracks = try TrackInputScanning.scanTracks(in: dirURL, relativeTo: cwdURL)

        let data = try JSONCoding.configEncoder().encode(tracks)

        let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tracks.superscribe.json")
        try data.write(to: outputURL)
        print("Created \(outputURL.path) with \(tracks.count) track(s).")
    }

}
