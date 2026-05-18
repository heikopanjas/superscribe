import ArgumentParser
import Foundation
import SuperscribeKit

// MARK: - Backend factory

/// Resolves the effective backend and model from CLI options + user config.
///
/// Priority: explicit CLI flag > user config > built-in defaults.
func resolveBackendAndModel(
    cliBackend: Backend?,
    cliModel: String?
) -> (backend: Backend, model: String) {
    let config = UserConfig.load()

    let backend = cliBackend ?? config.resolvedDefaultBackend()

    let model: String
    if let explicit = cliModel {
        model = explicit
    }
    else if let saved = config.defaultModel(for: backend) {
        model = saved
    }
    else {
        // Built-in defaults sourced from each backend's ModelRegistry.
        model = builtInDefaultModel(for: backend)
    }

    return (backend, model)
}

/// Returns the built-in default model id for a backend.
func builtInDefaultModel(for backend: Backend) -> String {
    switch backend {
        case .parakeet: return ParakeetBackend.defaultModelId
        case .whisper: return WhisperBackend.defaultModelId
        case .appleSpeech: return ""
    }
}

/// Returns a `Transcriber` for the given backend + model.
func makeTranscriber(backend: Backend, model: String) throws -> any Transcriber {
    switch backend {
        case .parakeet:
            guard ParakeetBackend.isAvailable else {
                throw BackendError.unavailable("Parakeet requires Apple Silicon")
            }
            return ParakeetBackend(model: model)
        case .whisper:
            guard WhisperBackend.isAvailable else {
                throw BackendError.unavailable("Whisper requires Apple Silicon")
            }
            return WhisperBackend(model: model)
        case .appleSpeech:
            throw BackendError.unavailable("Apple Speech backend not yet implemented (requires macOS 26)")
    }
}

enum BackendError: Error, CustomStringConvertible {
    case unavailable(String)
    var description: String {
        switch self { case .unavailable(let msg): return msg
        }
    }
}

// MARK: - Progress helper

private let progressQueue = DispatchQueue(label: "superscribe.progress", qos: .utility)

func makeProgressHandler() -> @Sendable (TranscriptionProgress) -> Void {
    { progress in
        let pct = Int(Double(progress.overallCompleted) / Double(max(1, progress.overallTotal)) * 100)
        let line =
            "\r[\(progress.speaker)] segment \(progress.segmentIndex)/\(progress.totalSegments)  —  overall \(progress.overallCompleted)/\(progress.overallTotal) (\(pct)%)"
        let data = Data((line + "  ").utf8)
        progressQueue.async { FileHandle.standardError.write(data) }
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return String(format: "%.1fs", seconds)
    }
    let m = Int(seconds) / 60
    let s = seconds - Double(m * 60)
    return String(format: "%dm %04.1fs", m, s)
}

// MARK: - Conversion progress

/// Throttled per-track stderr progress reporter for audio conversion.
/// Emits at most ~10 updates per second per track and a final 100% line.
final class ConversionProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmitted: [String: Date] = [:]
    private var lastFraction: [String: Double] = [:]
    private let throttle: TimeInterval = 0.1

    func handler() -> @Sendable (ConversionProgress) -> Void {
        { [weak self] progress in
            self?.handle(progress)
        }
    }

    private func handle(_ progress: ConversionProgress) {
        let key = progress.source.path
        let now = Date()
        var shouldEmit = false
        var isFinal = false
        lock.lock()
        let last = lastEmitted[key]
        let prevFraction = lastFraction[key] ?? -1
        isFinal = progress.fraction >= 1.0 && prevFraction < 1.0
        if isFinal || last == nil || now.timeIntervalSince(last!) >= throttle {
            lastEmitted[key] = now
            lastFraction[key] = progress.fraction
            shouldEmit = true
        }
        lock.unlock()
        guard shouldEmit else { return }

        let pct = Int((progress.fraction * 100).rounded())
        let name = progress.source.lastPathComponent
        let suffix = isFinal ? "\n" : ""
        let line = "\rConverting \(name) [\(pct)%]\u{1B}[K\(suffix)"
        progressQueue.async { FileHandle.standardError.write(Data(line.utf8)) }
    }
}

// MARK: - Download progress helper

func makeDownloadProgressHandler() -> @Sendable (DownloadProgress) -> Void {
    { p in
        var line = "\rDownloading \(p.modelId) [\(p.filesCompleted)/\(p.filesTotal)]"
        if let total = p.bytesTotal {
            let pct = Int(Double(p.bytesCompleted) / Double(max(1, total)) * 100)
            line += "  \(formatBytes(p.bytesCompleted))/\(formatBytes(total)) (\(pct)%)"
        }
        else {
            line += "  \(formatBytes(p.bytesCompleted))"
        }
        if let bps = p.bytesPerSecond, bps > 0 {
            line += "  \(formatBytes(Int64(bps)))/s"
        }
        if !p.currentFile.isEmpty {
            let short = (p.currentFile as NSString).lastPathComponent
            line += "  \(short)"
        }
        let data = Data((line + "  \u{1B}[K").utf8)
        FileHandle.standardError.write(data)
    }
}

/// If `model` isn't installed for `backend`, look it up in the catalog
/// (auto-fetch if missing) and install it via `ModelInstaller`.
/// No-op when the model is already on disk.
func ensureModelInstalled(_ model: String, backend: Backend) async throws {
    let installed = (try? installedModels(for: backend)) ?? []
    if installed.contains(where: { $0.id == model }) { return }

    FileHandle.standardError.write(
        Data(
            "Model '\(model)' not installed for backend '\(backend.rawValue)'; downloading...\n".utf8
        )
    )

    let (entry, _) = try await catalog(for: backend, forceRefresh: false)
    guard let info = entry.models.first(where: { $0.id == model }) else {
        throw ModelInstallationError.unknownModel(
            model: model,
            backend: backend,
            available: entry.models.map(\.id)
        )
    }
    _ = try await ModelInstaller.install(
        model: info,
        backend: backend,
        onProgress: makeDownloadProgressHandler()
    )
    // Clear the progress line.
    FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    FileHandle.standardError.write(
        Data("Installed '\(model)' for backend '\(backend.rawValue)'.\n".utf8)
    )
}

// MARK: - transcribe

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Detect speech in each track and produce an intermediate transcript."
    )

    @OptionGroup var options: TranscribeOptions

    mutating func run() async throws {
        let (backend, model) = resolveBackendAndModel(
            cliBackend: options.backend, cliModel: options.model
        )
        FileHandle.standardError.write(
            Data("Using backend: \(backend.rawValue), model: \(model)\n".utf8)
        )
        try await ensureModelInstalled(model, backend: backend)
        let transcriber = try makeTranscriber(backend: backend, model: model)

        let pipelineConfig = PipelineConfig(
            tracks: options.trackInputs,
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
        let outputURL = URL(fileURLWithPath: options.output)
        try data.write(to: outputURL)

        let trackCount = transcript.tracks.count
        let segCount = transcript.tracks.reduce(0) { $0 + $1.segments.count }
        FileHandle.standardError.write(
            Data("Transcribed \(segCount) segments from \(trackCount) track(s) in \(formatDuration(transcribeDuration))\n".utf8)
        )
        FileHandle.standardError.write(
            Data("Output: \(options.output)\n".utf8)
        )
    }
}

// MARK: - merge

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

// MARK: - run

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Transcribe and merge in a single pass."
    )

    @OptionGroup var transcribeOptions: TranscribeOptions
    @OptionGroup var mergeOptions: MergeOptions

    @Flag(name: .long, help: "Save the intermediate file (default: discard).")
    var keepIntermediate: Bool = false

    mutating func run() async throws {
        let (backend, model) = resolveBackendAndModel(
            cliBackend: transcribeOptions.backend, cliModel: transcribeOptions.model
        )
        FileHandle.standardError.write(
            Data("Using backend: \(backend.rawValue), model: \(model)\n".utf8)
        )
        try await ensureModelInstalled(model, backend: backend)
        let transcriber = try makeTranscriber(backend: backend, model: model)

        let pipelineConfig = PipelineConfig(
            tracks: transcribeOptions.trackInputs,
            transcriptionConfig: transcribeOptions.transcriptionConfig(model: model),
            analyzerConfig: transcribeOptions.analyzerConfig,
            session: nil
        )

        let audioCache: ConvertedAudioCache? = transcribeOptions.noCache ? nil : ConvertedAudioCache()
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

        let segCount = transcript.tracks.reduce(0) { $0 + $1.segments.count }
        let trackCount = transcript.tracks.count
        FileHandle.standardError.write(
            Data("Transcribed \(segCount) segments from \(trackCount) track(s) in \(formatDuration(transcribeDuration))\n".utf8)
        )

        if keepIntermediate {
            let data = try IntermediateTranscript.jsonEncoder().encode(transcript)
            let outputURL = URL(fileURLWithPath: transcribeOptions.output)
            try data.write(to: outputURL)
        }

        let output = MergeCommand.renderMerged(transcript, options: mergeOptions)

        if let path = mergeOptions.mergeOutput {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
        }
        else {
            print(output, terminator: "")
        }
    }
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
// MARK: - models

/// Fetches the catalog for `backend`, using the on-disk `CatalogStore` when
/// possible. When `forceRefresh` is true, or no entry exists for the
/// backend yet, hits the network and persists the response.
func catalog(
    for backend: Backend,
    forceRefresh: Bool = false
) async throws -> (entry: CatalogEntry, refreshed: Bool) {
    if !forceRefresh,
        let existing = (try? CatalogStore.load())?.entry(for: backend)
    {
        return (existing, false)
    }
    let models = try await remoteModels(for: backend)
    let entry = CatalogEntry(fetchedAt: Date(), models: models)
    try CatalogStore.update(entry, for: backend)
    return (entry, true)
}

/// Backend → its `remoteModels()` static call.
func remoteModels(for backend: Backend) async throws -> [RemoteModelInfo] {
    switch backend {
        case .parakeet: return try await ParakeetBackend.remoteModels()
        case .whisper: return try await WhisperBackend.remoteModels()
        case .appleSpeech: return []
    }
}

/// Backend → its `installedModels()` static call.
func installedModels(for backend: Backend) throws -> [InstalledModelInfo] {
    switch backend {
        case .parakeet: return try ParakeetBackend.installedModels()
        case .whisper: return try WhisperBackend.installedModels()
        case .appleSpeech: return []
    }
}

struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List, refresh, or set defaults for transcription models."
    )

    @Option(name: .long, help: "Backend (parakeet, whisper). Defaults to your configured backend.")
    var backend: Backend?

    @Flag(name: .long, help: "List models. Implicit when no other verb is given.")
    var list: Bool = false

    @Option(name: .customLong("set-default"), help: "Set the default model id for the backend.")
    var setDefault: String?

    @Flag(name: .long, help: "With --list: show the remote catalog (cached). Without: refresh first.")
    var remote: Bool = false

    @Flag(name: .long, help: "Re-fetch the remote catalog for the backend, updating the cache.")
    var refresh: Bool = false

    @Option(name: .long, help: "Download a model by id (e.g. v3, large-v3_turbo).")
    var download: String?

    @Option(name: .long, help: "Remove an installed model by id.")
    var rm: String?

    @Flag(name: .long, help: "Skip confirmation prompts (use with --rm).")
    var yes: Bool = false

    @Flag(name: .long, help: "Emit machine-readable JSON (only with --list).")
    var json: Bool = false

    mutating func validate() throws {
        // Verb exclusivity: at most one primary verb, with --refresh + --list
        // allowed (refresh-then-list).
        let verbs: [(String, Bool)] = [
            ("--list", list),
            ("--set-default", setDefault != nil),
            ("--download", download != nil),
            ("--rm", rm != nil)
        ]
        let activeVerbs = verbs.filter { $0.1 }.map(\.0)
        if activeVerbs.count > 1 {
            throw ValidationError(
                "Only one of \(activeVerbs.joined(separator: ", ")) may be used at once."
            )
        }
        if (download != nil || rm != nil) && refresh {
            throw ValidationError("--refresh cannot be combined with --download or --rm.")
        }
        if remote && (setDefault != nil || download != nil || rm != nil) {
            throw ValidationError("--remote applies only to --list.")
        }
        if json && (setDefault != nil || download != nil || rm != nil) {
            throw ValidationError("--json applies only to --list.")
        }
    }

    private var resolvedBackend: Backend {
        backend ?? UserConfig.load().resolvedDefaultBackend()
    }

    mutating func run() async throws {
        let backend = resolvedBackend

        if let modelId = download {
            try await runDownload(modelId, backend: backend)
            return
        }
        if let modelId = rm {
            try runRemove(modelId, backend: backend)
            return
        }
        if let modelId = setDefault {
            try await runSetDefault(modelId, backend: backend)
            return
        }
        if refresh && !list {
            try await runRefresh(backend: backend)
            return
        }
        // Default verb is --list (with optional --remote and/or --refresh).
        try await runList(backend: backend)
    }

    // MARK: - Verbs

    private func runList(backend: Backend) async throws {
        if remote {
            let (entry, refreshed) = try await catalog(for: backend, forceRefresh: refresh)
            let installed = (try? installedModels(for: backend)) ?? []
            let installedIds = Set(installed.map(\.id))
            if json {
                printJSON(entry.models)
            }
            else {
                renderRemoteList(
                    entry,
                    installedIds: installedIds,
                    backend: backend,
                    refreshed: refreshed
                )
            }
            return
        }

        // Local install scan.
        let installed = try installedModels(for: backend)
        if json {
            printJSON(installed)
        }
        else {
            renderInstalledList(installed, backend: backend)
        }
    }

    private func runRefresh(backend: Backend) async throws {
        let (entry, _) = try await catalog(for: backend, forceRefresh: true)
        print(
            "Refreshed \(backend.rawValue) catalog: \(entry.models.count) model(s), fetched \(formatDate(entry.fetchedAt))."
        )
    }

    private func runDownload(_ modelId: String, backend: Backend) async throws {
        let installPath = try ModelInstaller.installPath(for: modelId, backend: backend)
        if ModelInstaller.isInstalled(at: installPath, backend: backend) {
            print("Already installed at \(installPath.path)")
            return
        }
        let (entry, _) = try await catalog(for: backend, forceRefresh: false)
        guard let info = entry.models.first(where: { $0.id == modelId }) else {
            throw ModelInstallationError.unknownModel(
                model: modelId,
                backend: backend,
                available: entry.models.map(\.id)
            )
        }
        let final = try await ModelInstaller.install(
            model: info,
            backend: backend,
            onProgress: makeDownloadProgressHandler()
        )
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
        print("Installed at \(final.path)")
    }

    private func runRemove(_ modelId: String, backend: Backend) throws {
        let installed = (try? installedModels(for: backend)) ?? []
        guard let entry = installed.first(where: { $0.id == modelId }) else {
            let valid = installed.map(\.id).joined(separator: ", ")
            throw ValidationError(
                "Model '\(modelId)' is not installed for backend '\(backend.rawValue)'. "
                    + "Installed: \(valid.isEmpty ? "(none)" : valid)"
            )
        }
        if !yes {
            FileHandle.standardError.write(
                Data("Remove '\(modelId)' (\(entry.path.path))? [y/N] ".utf8)
            )
            let answer = readLine(strippingNewline: true)?.lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                print("Aborted.")
                return
            }
        }
        try FileManager.default.removeItem(at: entry.path)
        print("Removed \(entry.path.path)")
    }

    private func runSetDefault(_ modelId: String, backend: Backend) async throws {
        let (entry, _) = try await catalog(for: backend, forceRefresh: false)
        guard entry.models.contains(where: { $0.id == modelId }) else {
            let valid = entry.models.map(\.id).joined(separator: ", ")
            throw ValidationError(
                "Unknown model '\(modelId)' for backend '\(backend.rawValue)'. Available: \(valid)"
            )
        }
        var config = UserConfig.load()
        config.setDefaultModel(modelId, for: backend)
        try config.save()
        print("Default model for '\(backend.rawValue)' set to '\(modelId)'.")
    }

    // MARK: - Rendering

    private func renderInstalledList(_ models: [InstalledModelInfo], backend: Backend) {
        let userDefault = UserConfig.load().defaultModel(for: backend)
        let builtinDefault = builtInDefaultModel(for: backend)
        if models.isEmpty {
            print("No models installed for backend '\(backend.rawValue)'.")
            print("Try: superscribe models --list --remote --backend \(backend.rawValue)")
            return
        }
        let idWidth = max(8, models.map(\.id.count).max() ?? 0)
        for m in models {
            let marker = defaultMarker(
                id: m.id, userDefault: userDefault, builtinDefault: builtinDefault
            )
            let size = m.sizeBytes.map(formatBytes) ?? "—"
            let paddedId = m.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
            print("  \(paddedId)  \(size.leftPad(toLength: 10))  \(m.path.path)\(marker)")
        }
    }

    private func renderRemoteList(
        _ entry: CatalogEntry,
        installedIds: Set<String>,
        backend: Backend,
        refreshed: Bool
    ) {
        let userDefault = UserConfig.load().defaultModel(for: backend)
        let builtinDefault = builtInDefaultModel(for: backend)
        if entry.models.isEmpty {
            print("Remote catalog for '\(backend.rawValue)' is empty.")
            return
        }
        let idWidth = max(8, entry.models.map(\.id.count).max() ?? 0)
        for m in entry.models {
            let marker = defaultMarker(
                id: m.id, userDefault: userDefault, builtinDefault: builtinDefault
            )
            let installedTag = installedIds.contains(m.id) ? " (installed)" : ""
            let size = m.totalSizeBytes.map(formatBytes) ?? "—"
            let updated = m.lastModified.map(formatDate) ?? "—"
            let paddedId = m.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
            print("  \(paddedId)  \(size.leftPad(toLength: 10))  \(updated)\(installedTag)\(marker)")
        }
        let stamp = formatDate(entry.fetchedAt)
        let suffix = refreshed ? " (refreshed)" : ""
        print("\nfetched \(stamp)\(suffix)")
    }

    private func defaultMarker(
        id: String, userDefault: String?, builtinDefault: String
    ) -> String {
        if userDefault == id { return "  (user default)" }
        if userDefault == nil && id == builtinDefault { return "  (default)" }
        return ""
    }

    private func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value),
            let s = String(data: data, encoding: .utf8)
        {
            print(s)
        }
    }
}

// MARK: - Formatting helpers

func formatBytes(_ bytes: Int64) -> String {
    let units: [(threshold: Double, suffix: String)] = [
        (1024 * 1024 * 1024, "GiB"),
        (1024 * 1024, "MiB"),
        (1024, "KiB")
    ]
    let value = Double(bytes)
    for (threshold, suffix) in units where value >= threshold {
        return String(format: "%.1f %@", value / threshold, suffix)
    }
    return "\(bytes) B"
}

func formatDate(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return f.string(from: date)
}

extension String {
    fileprivate func leftPad(toLength length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}

// MARK: - backends

struct BackendsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backends",
        abstract: "List available backends, set the default, or show capabilities."
    )

    @Option(name: .long, help: "Set the default backend.")
    var setDefault: Backend?

    @Flag(name: [.long, .customLong("caps")], help: "Print capabilities of the current default backend.")
    var capabilities: Bool = false

    mutating func run() throws {
        if let backend = setDefault {
            var config = UserConfig.load()
            config.setDefaultBackend(backend)
            try config.save()
            print("Default backend set to '\(backend.rawValue)'.")
        }
        else if capabilities {
            try printCapabilities()
        }
        else {
            let config = UserConfig.load()
            let userDefault = config.resolvedDefaultBackend()
            for backend in Backend.allCases {
                let marker = (backend == userDefault) ? " (default)" : ""
                print("  \(backend.rawValue)\(marker)")
            }
        }
    }

    private func printCapabilities() throws {
        let (backend, model) = resolveBackendAndModel(cliBackend: nil, cliModel: nil)
        let transcriber = try makeTranscriber(backend: backend, model: model)
        let caps = transcriber.capabilities
        let fmt = caps.requiredAudioFormat

        print("Backend:        \(caps.displayName)")
        print("Audio format:   \(fmt.sampleRate) Hz, \(fmt.channels == 1 ? "mono" : "\(fmt.channels) channels")")
        print("Default model:  \(caps.defaultModelId)")
        print("")
        print("Use `superscribe models --list --remote --backend \(backend.rawValue)` for the full catalog.")
    }
}
