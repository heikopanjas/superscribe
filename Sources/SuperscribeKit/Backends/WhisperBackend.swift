import Foundation
@preconcurrency import WhisperKit

/// WhisperKit backend for on-device speech-to-text using OpenAI Whisper
/// models compiled to CoreML.
///
/// Models are downloaded automatically on first use from HuggingFace and
/// cached locally. Supports word-level timestamps, language hints, and
/// prompt tokens for context.
public actor WhisperBackend: Transcriber {
    private var whisperKit: WhisperKit?
    private let modelName: String
    private var loadingTask: Task<WhisperKit, any Error>?

    /// - Parameter model: Whisper model variant (e.g. `"large-v3_turbo"`).
    ///   Defaults to `"large-v3_turbo"` for the best speed/accuracy tradeoff.
    public init(model: String = "large-v3_turbo") {
        self.modelName = model
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
            displayName: "Whisper (WhisperKit)",
            defaultModelId: WhisperBackend.defaultModelId
        )
    }

    // MARK: - Transcriber

    public func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: SuperscribeKit.TranscriptionConfig
    ) async throws -> SegmentTranscription {
        let pipe = try await ensureLoaded()

        guard !samples.isEmpty else {
            return SegmentTranscription(segment: segment, words: [])
        }

        var options = DecodingOptions(wordTimestamps: true)
        if let lang = config.language {
            options.language = lang
        }
        if let prompt = config.prompt {
            options.promptTokens =
                pipe.tokenizer?.encode(text: prompt).filter {
                    $0 < (pipe.tokenizer?.specialTokens.specialTokenBegin ?? .max)
                } ?? []
        }

        let whisperResults = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        let wkWords = extractWords(from: whisperResults)
        let timedWords = wkWords.map { w in
            TimedWord(
                text: w.text,
                start: TimeInterval(w.start) + segment.start,
                end: TimeInterval(w.end) + segment.start
            )
        }
        return SegmentTranscription(segment: segment, words: timedWords)
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> WhisperKit {
        if let pipe = whisperKit {
            return pipe
        }
        if let task = loadingTask {
            return try await task.value
        }
        let task = Task { [self] () async throws -> WhisperKit in
            // Load strictly from local disk; the install pipeline is
            // responsible for placing files there.
            guard let folder = Self.localModelFolder(for: modelName) else {
                throw ModelInstallationError.modelNotInstalled(
                    model: modelName, backend: .whisper
                )
            }
            FileHandle.standardError.write(
                Data("Loading Whisper model \(modelName) from local cache...\n".utf8)
            )
            let config = WhisperKitConfig(modelFolder: folder)
            let pipe = try await WhisperKit(config)
            self.whisperKit = pipe
            return pipe
        }
        loadingTask = task
        let pipe = try await task.value
        loadingTask = nil
        return pipe
    }

    /// Returns the local model folder path if the model is already cached.
    static func localModelFolder(for model: String) -> String? {
        let coremlDir = whisperKitCacheDirectory()
            .appendingPathComponent("openai_whisper-\(model)")

        // Check that the directory exists and contains at least one .mlmodelc bundle.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: coremlDir.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return nil
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: coremlDir.path)) ?? []
        guard contents.contains(where: { $0.hasSuffix(".mlmodelc") }) else {
            return nil
        }
        return coremlDir.path
    }

    /// The directory under `~/Documents/huggingface/...` that WhisperKit uses
    /// to cache CoreML model folders.
    static func whisperKitCacheDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return
            home
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml")
    }
}
