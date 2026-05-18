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

    mutating func validate() throws {
        let hasTrack = !options.track.isEmpty
        if let _ = createInput {
            if hasTrack == true { throw ValidationError("--create-input may not be combined with --track.") }
            if input != nil { throw ValidationError("--create-input may not be combined with --input.") }
        }
        if input != nil, hasTrack == true {
            throw ValidationError("--input may not be combined with --track.")
        }
    }

    mutating func run() async throws {
        if let dir = createInput {
            try runCreateInput(directory: dir)
            return
        }

        let resolvedTracks: [TrackInput]
        if let inputFile = input {
            resolvedTracks = try loadTrackInputs(from: inputFile)
        }
        else {
            resolvedTracks = options.trackInputs
        }

        let (backend, model) = BackendManager.resolveBackendAndModel(
            cliBackend: options.backend, cliModel: options.model
        )
        FileHandle.standardError.write(
            Data("Using backend: \(backend.rawValue), model: \(model)\n".utf8)
        )
        try await ModelManager.ensureModelInstalled(model, backend: backend)
        let transcriber = try BackendManager.makeTranscriber(backend: backend, model: model)

        let pipelineConfig = PipelineConfig(
            tracks: resolvedTracks,
            transcriptionConfig: options.transcriptionConfig(model: model),
            analyzerConfig: options.analyzerConfig,
            session: nil
        )

        let audioCache: ConvertedAudioCache? = options.noCache ? nil : ConvertedAudioCache()
        let conversionReporter = ConversionProgressReporter()

        let pipeline = TranscribePipeline(
            transcriber: transcriber,
            config: pipelineConfig,
            audioCache: audioCache,
            onProgress: makeProgressHandler(),
            onConversionProgress: conversionReporter.handler()
        )

        let transcribeStart = Date()
        let transcript = try await pipeline.run()
        let transcribeDuration = Date().timeIntervalSince(transcribeStart)

        // Clear progress line.
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))

        let data = try IntermediateTranscript.jsonEncoder().encode(transcript)
        let outputPath =
            options.output.isEmpty
            ? "transcript.superscribe.\(backend.rawValue).json"
            : options.output
        let outputURL = URL(fileURLWithPath: outputPath)
        try data.write(to: outputURL)

        let trackCount = transcript.tracks.count
        let segCount = transcript.tracks.reduce(0) { $0 + $1.segments.count }
        FileHandle.standardError.write(
            Data("Transcribed \(segCount) segments from \(trackCount) track(s) in \(formatDuration(transcribeDuration))\n".utf8)
        )
        FileHandle.standardError.write(
            Data("Output: \(outputPath)\n".utf8)
        )
    }

    // MARK: - --create-input

    private func runCreateInput(directory: String) throws {
        let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir) == true, isDir.boolValue == true else {
            throw ValidationError("\(directory): not a directory.")
        }

        let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "ogg", "mp4", "mov", "caf", "opus"]
        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles
        )
        let audioFiles =
            contents
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard audioFiles.isEmpty == false else {
            throw ValidationError("No audio files found in \(directory).")
        }

        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var tracks: [String: String] = [:]
        for (i, url) in audioFiles.enumerated() {
            let absPath = url.standardizedFileURL.path
            let cwdPath = cwdURL.standardizedFileURL.path + "/"
            let relPath =
                absPath.hasPrefix(cwdPath)
                ? String(absPath.dropFirst(cwdPath.count))
                : absPath
            tracks["speaker-\(i + 1)"] = relPath
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tracks)

        let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tracks.superscribe.json")
        try data.write(to: outputURL)
        print("Created \(outputURL.path) with \(audioFiles.count) track(s).")
    }

    // MARK: - --input

    private func loadTrackInputs(from filePath: String) throws -> [TrackInput] {
        let fileURL = URL(fileURLWithPath: filePath)
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        let data = try Data(contentsOf: fileURL)
        let mapping = try JSONDecoder().decode([String: String].self, from: data)

        guard mapping.isEmpty == false else {
            throw ValidationError("\(filePath): track mapping is empty.")
        }

        return mapping.sorted { $0.key < $1.key }.map { speaker, filename in
            TrackInput(speaker: speaker, file: cwdURL.appendingPathComponent(filename))
        }
    }
}
