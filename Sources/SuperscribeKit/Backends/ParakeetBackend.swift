import AVFoundation
import FluidAudio
import Foundation

/// FluidAudio Parakeet TDT v3 backend for on-device speech-to-text.
///
/// Uses the Apple Neural Engine for inference, keeping the GPU free.
/// Models are downloaded automatically on first use and cached at
/// `~/.cache/fluidaudio/Models/`.
public actor ParakeetBackend: Transcriber {
    private var asrManager: AsrManager?
    private var models: AsrModels?
    private let modelVersion: AsrModelVersion
    private var loadingTask: Task<AsrManager, any Error>?

    /// - Parameter model: Model version string. Accepted values:
    ///   `"v3"` (multilingual, default), `"v2"` (English-only),
    ///   `"tdt-ctc-110m"`, `"tdt-ja"`.
    public init(model: String = "v3") {
        self.modelVersion = Self.parseModelVersion(model)
    }

    private static func parseModelVersion(_ model: String) -> AsrModelVersion {
        switch model.lowercased() {
            case "v2": return .v2
            case "v3": return .v3
            case "tdt-ctc-110m", "tdtctc110m", "110m": return .tdtCtc110m
            case "tdt-ja", "tdtja", "ja": return .tdtJa
            default: return .v3
        }
    }

    public static var isAvailable: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    public nonisolated var capabilities: BackendCapabilities {
        BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Parakeet TDT \(modelVersion) (FluidAudio)",
            defaultModelId: ParakeetBackend.defaultModelId
        )
    }

    // MARK: - Transcriber

    public func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        let manager = try await ensureLoaded()

        guard samples.isEmpty == false else {
            return SegmentTranscription(segment: segment, words: [])
        }

        // Map config.language to FluidAudio's Language enum.
        let language: Language? = config.language.flatMap { Language(rawValue: $0) }

        // Transcribe with a fresh decoder state per segment.
        var decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount
        )
        let asrResult = try await manager.transcribe(
            samples,
            decoderState: &decoderState,
            language: language
        )

        return mapResult(asrResult, segment: segment)
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> AsrManager {
        if let manager = asrManager {
            return manager
        }
        // Coalesce concurrent callers onto a single load task
        // to avoid actor-reentrancy double-loads.
        if let task = loadingTask {
            return try await task.value
        }
        let task = Task { [self] () async throws -> AsrManager in
            // Resolve install dir from our short id and require it to exist.
            // Install pipeline is responsible for downloads.
            let modelId = ParakeetBackend.shortIdForVersion(modelVersion)
            let installDir = ParakeetBackend.installPath(for: modelId)
            guard FileManager.default.fileExists(atPath: installDir.path) == true else {
                throw ModelInstallationError.modelNotInstalled(
                    model: modelId, backend: .parakeet
                )
            }
            FileHandle.standardError.write(
                Data("Loading Parakeet TDT \(modelVersion) models from local cache...\n".utf8)
            )
            // Note: FluidAudio's [INFO] log output is only emitted in DEBUG
            // builds (AppLogger uses #if DEBUG to gate console writes), so no
            // suppression is needed here.
            let loadedModels = try await AsrModels.load(
                from: installDir, version: modelVersion
            )
            let mgr = AsrManager()
            try await mgr.loadModels(loadedModels)
            self.models = loadedModels
            self.asrManager = mgr
            return mgr
        }
        loadingTask = task
        let manager = try await task.value
        loadingTask = nil
        return manager
    }

    private static func shortIdForVersion(_ v: AsrModelVersion) -> String {
        switch v {
            case .v2: return "v2"
            case .v3: return "v3"
            case .tdtCtc110m: return "tdt-ctc-110m"
            case .tdtJa: return "tdt-ja"
            default: return "v3"
        }
    }

    /// Map FluidAudio's `ASRResult` to our `SegmentTranscription`.
    private nonisolated func mapResult(
        _ asr: ASRResult,
        segment: SpeechSegment
    ) -> SegmentTranscription {
        let words: [TimedWord]

        if let timings = asr.tokenTimings, timings.isEmpty == false {
            // Merge sub-word tokens into word-level timings.
            words = mergeTokensIntoWords(timings, segmentOffset: segment.start)
        }
        else {
            // No token-level timings — emit entire text as a single word
            // spanning the segment.
            let text = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == true {
                words = []
            }
            else {
                words = [TimedWord(text: text, start: segment.start, end: segment.end)]
            }
        }

        return SegmentTranscription(segment: segment, words: words)
    }

    /// Merge Parakeet's sub-word `TokenTiming`s (SentencePiece ▁-prefixed)
    /// into whole-word `TimedWord`s.
    private nonisolated func mergeTokensIntoWords(
        _ timings: [TokenTiming],
        segmentOffset: TimeInterval
    ) -> [TimedWord] {
        var words: [TimedWord] = []
        var currentText = ""
        var wordStart: TimeInterval = 0
        var wordEnd: TimeInterval = 0

        for timing in timings {
            let token = timing.token

            // SentencePiece word boundary: leading ▁ means new word.
            let isNewWord = token.hasPrefix("▁") || token.hasPrefix(" ")

            if isNewWord == true && currentText.isEmpty == false {
                words.append(
                    TimedWord(
                        text: currentText,
                        start: wordStart + segmentOffset,
                        end: wordEnd + segmentOffset
                    ))
                currentText = ""
            }

            let cleaned =
                token
                .replacingOccurrences(of: "▁", with: "")
                .replacingOccurrences(of: " ", with: "")

            if currentText.isEmpty == true {
                wordStart = timing.startTime
            }
            currentText += cleaned
            wordEnd = timing.endTime
        }

        // Flush last word.
        if currentText.isEmpty == false {
            words.append(
                TimedWord(
                    text: currentText,
                    start: wordStart + segmentOffset,
                    end: wordEnd + segmentOffset
                ))
        }

        return words
    }
}
