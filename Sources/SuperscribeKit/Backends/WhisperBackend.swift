import Foundation
import whisper

/// Sendable box for a C `OpaquePointer` (whisper_context *).
/// whisper_context is not thread-safe for writes, but we only read from it
/// (via per-call whisper_state), so the isolation is safe.
private final class WhisperContext: @unchecked Sendable {
    let ptr: OpaquePointer
    init(_ ptr: OpaquePointer) { self.ptr = ptr }
    deinit { whisper_free(ptr) }
}

/// whisper.cpp backend for on-device speech-to-text using OpenAI Whisper GGML
/// models with Metal GPU acceleration.
///
/// Each instance owns a single `whisper_context` loaded from a `.bin` model
/// file on disk. A per-call `whisper_state` provides safe concurrent use
/// across the two-track pipeline without sharing mutable state between tasks.
public actor WhisperBackend: Transcriber {
    private var ctx: WhisperContext?
    private let modelId: String
    private var loadingTask: Task<WhisperContext, any Error>?

    /// - Parameter model: GGML model variant, e.g. `"large-v3-turbo"`, `"base"`,
    ///   `"medium-q5_0"`. Defaults to `"large-v3-turbo"`.
    public init(model: String = WhisperBackend.defaultModelId) {
        self.modelId = model
    }

    deinit {
        // whisper_free is handled by WhisperContext deinit
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
            displayName: "Whisper (whisper.cpp)",
            defaultModelId: WhisperBackend.defaultModelId
        )
    }

    // MARK: - Transcriber

    public func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        let context = try await ensureLoaded()

        guard samples.isEmpty == false else {
            return SegmentTranscription(segment: segment, words: [])
        }

        // Allocate per-call state so concurrent transcriptions don't share
        // mutable whisper internals. (Logging is already silenced globally.)
        guard let state = whisper_init_state(context.ptr) else {
            throw WhisperError.stateInitFailed
        }
        defer { whisper_free_state(state) }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.token_timestamps = true
        // Disable temperature fallbacks: when the decoder's confidence drops,
        // whisper re-runs the segment at increasing temperatures, which can
        // cost 5-10x on hard segments. Setting temperature_inc to 0 keeps the
        // greedy first pass and skips the fallback loop entirely.
        params.temperature_inc = 0.0

        // Language hint: whisper expects a short ISO code like "en", "ja", etc.
        // We must keep the C string alive for the duration of the call.
        let languageCStr: [CChar]? = config.language.flatMap { $0.cString(using: .utf8) }
        if languageCStr != nil {
            params.language = languageCStr!.withUnsafeBufferPointer { $0.baseAddress }
        }

        // Initial prompt as a C string.
        let promptCStr: [CChar]? = config.prompt.flatMap { $0.cString(using: .utf8) }
        if promptCStr != nil {
            params.initial_prompt = promptCStr!.withUnsafeBufferPointer { $0.baseAddress }
        }

        let rc = samples.withUnsafeBufferPointer { buf in
            whisper_full_with_state(context.ptr, state, params, buf.baseAddress, Int32(buf.count))
        }
        guard rc == 0 else {
            throw WhisperError.transcriptionFailed(code: rc)
        }

        let words = extractTimedWords(ctx: context, state: state, segmentOffset: segment.start)
        return SegmentTranscription(segment: segment, words: words)
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> WhisperContext {
        if let c = ctx { return c }
        if let task = loadingTask { return try await task.value }

        let task = Task { [self] () async throws -> WhisperContext in
            let binPath = WhisperBackend.installPath(for: modelId).path
            guard FileManager.default.fileExists(atPath: binPath) == true else {
                throw ModelInstallationError.modelNotInstalled(
                    model: modelId, backend: .whisperCpp
                )
            }
            FileHandle.standardError.write(
                Data("Loading Whisper model \(modelId)...\n".utf8)
            )
            var ctxParams = whisper_context_default_params()
            ctxParams.use_gpu = true
            // Fused flash-attention kernels on Metal: 20-40% faster encode +
            // decode with no quality loss for f16/quantized GGML models.
            ctxParams.flash_attn = true
            // Permanently silence all ggml/whisper C-library log output.
            // Both sinks must be set: ggml_log_set covers ggml_metal_init and
            // other ggml-level messages; whisper_log_set covers whisper-level
            // messages. Neither is restored — we manage all user-facing output
            // ourselves and never want internal C-library logging on stderr.
            ggml_log_set({ _, _, _ in }, nil)
            whisper_log_set({ _, _, _ in }, nil)
            let ptr = whisper_init_from_file_with_params(binPath, ctxParams)
            guard let ptr else {
                throw WhisperError.contextInitFailed(path: binPath)
            }
            let c = WhisperContext(ptr)
            self.ctx = c
            return c
        }
        loadingTask = task
        let c = try await task.value
        loadingTask = nil
        return c
    }

    /// Walk whisper_state segments/tokens and merge sub-word pieces into
    /// whole-word `TimedWord`s. whisper.cpp uses a leading space to mark word
    /// boundaries (same convention as SentencePiece ▁).
    private nonisolated func extractTimedWords(
        ctx: WhisperContext,
        state: OpaquePointer,
        segmentOffset: TimeInterval
    ) -> [TimedWord] {
        var words: [TimedWord] = []
        let nSegments = Int(whisper_full_n_segments_from_state(state))

        for s in 0 ..< nSegments {
            let nTokens = Int(whisper_full_n_tokens_from_state(state, Int32(s)))
            var currentText = ""
            var wordStart: TimeInterval = 0
            var wordEnd: TimeInterval = 0

            for t in 0 ..< nTokens {
                let data = whisper_full_get_token_data_from_state(state, Int32(s), Int32(t))
                guard let rawPtr = whisper_full_get_token_text_from_state(ctx.ptr, state, Int32(s), Int32(t)) else {
                    continue
                }
                let token = String(cString: rawPtr)

                // Skip special tokens: negative ids, and whisper's bracket
                // tokens ([_BEG_], [_TT_N], [_EOT_], etc.) which have
                // positive ids but must never appear as visible text.
                guard data.id >= 0, token.hasPrefix("[_") == false else { continue }

                // A leading space marks a new word boundary.
                let isNewWord = token.hasPrefix(" ") || token.hasPrefix("▁")

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
                    .trimmingCharacters(in: CharacterSet(charactersIn: " "))

                if cleaned.isEmpty == false {
                    if currentText.isEmpty == true {
                        wordStart = TimeInterval(data.t0) / 100.0
                    }
                    currentText += cleaned
                    wordEnd = TimeInterval(data.t1) / 100.0
                }
            }

            if currentText.isEmpty == false {
                words.append(
                    TimedWord(
                        text: currentText,
                        start: wordStart + segmentOffset,
                        end: wordEnd + segmentOffset
                    ))
            }
        }
        return words
    }
}

// MARK: - Errors

enum WhisperError: Error, LocalizedError {
    case contextInitFailed(path: String)
    case stateInitFailed
    case transcriptionFailed(code: Int32)

    var errorDescription: String? {
        switch self {
            case .contextInitFailed(let p): return "whisper_context init failed for model at \(p)"
            case .stateInitFailed: return "whisper_init_state returned nil"
            case .transcriptionFailed(let c): return "whisper_full_with_state failed (code \(c))"
        }
    }
}
