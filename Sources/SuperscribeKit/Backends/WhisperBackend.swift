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

private func suppressLibraryLog(
    _ level: ggml_log_level,
    _ text: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) {}

/// whisper.cpp backend for on-device speech-to-text using OpenAI Whisper GGML
/// models. Encoder runs on the Apple Neural Engine when a Core ML bundle is
/// installed beside the `.bin`; otherwise Metal GPU. Decoder uses Metal.
///
/// Each instance owns a single `whisper_context` loaded from a `.bin` model
/// file on disk. A per-call `whisper_state` provides safe concurrent use
/// across the two-track pipeline without sharing mutable state between tasks.
public actor WhisperBackend: Transcriber {
    /// When `true`, `isAvailable` reports unavailable (for dispatch tests).
    nonisolated(unsafe) internal static var testForceUnavailable = false
    /// When `true`, `transcribe` throws `stateInitFailed` after load.
    nonisolated(unsafe) internal static var testForceStateInitFailed = false
    /// When `true`, `transcribe` throws `transcriptionFailed`.
    nonisolated(unsafe) internal static var testForceTranscriptionFailed = false
    /// When `true`, `extractTimedWords` skips tokens whose text pointer is nil.
    nonisolated(unsafe) internal static var testForceNilTokenText = false
    nonisolated(unsafe) internal static var testNilTokenTextSkipsRemaining = 0

    public nonisolated static var isAvailable: Bool {
        if testForceUnavailable == true { return false }
        return true
    }

    private let loader = LoadOnce<WhisperContext>()
    private let modelId: String

    /// - Parameter model: GGML model variant, e.g. `"large-v3-turbo"`, `"base"`,
    ///   `"medium-q5_0"`. Defaults to `"large-v3-turbo"`.
    public init(model: String = WhisperBackend.defaultModelId) {
        self.modelId = model
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

        // Allocate per-call state so concurrent transcriptions don't share
        // mutable whisper internals. (Logging is already silenced globally.)
        let state: OpaquePointer?
        if Self.testForceStateInitFailed == true {
            state = nil
        }
        else {
            state = whisper_init_state(context.ptr)
        }
        guard let state else {
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

        let rc: Int32
        if Self.testForceTranscriptionFailed == true {
            rc = -1
        }
        else {
            rc = samples.withUnsafeBufferPointer { buf in
                whisper_full_with_state(context.ptr, state, params, buf.baseAddress, Int32(buf.count))
            }
        }
        guard rc == 0 else {
            throw WhisperError.transcriptionFailed(code: rc)
        }

        let words = extractTimedWords(ctx: context, state: state, segmentOffset: segment.start)
        return SegmentTranscription(segment: segment, words: words)
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> WhisperContext {
        try await loader.get { [modelId] in
            let binURL = WhisperBackend.installPath(for: modelId)
            try ModelInstallSupport.requireInstalled(
                at: binURL, modelId: modelId, backend: .whisperCpp
            )
            let binPath = binURL.path
            FileHandle.standardError.write(
                Data("Loading Whisper model \(modelId)...\n".utf8)
            )
            var ctxParams = whisper_context_default_params()
            ctxParams.use_gpu = true
            ctxParams.flash_attn = true
            ggml_log_set(suppressLibraryLog, nil)
            whisper_log_set(suppressLibraryLog, nil)
            let ptr = whisper_init_from_file_with_params(binPath, ctxParams)
            guard let ptr else {
                throw WhisperError.contextInitFailed(path: binPath)
            }
            return WhisperContext(ptr)
        }
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
            var accumulator = TokenAccumulator()

            for t in 0 ..< nTokens {
                let data = whisper_full_get_token_data_from_state(state, Int32(s), Int32(t))
                let rawPtr: UnsafePointer<CChar>?
                if Self.testForceNilTokenText == true,
                    Self.testNilTokenTextSkipsRemaining > 0
                {
                    Self.testNilTokenTextSkipsRemaining -= 1
                    rawPtr = nil
                }
                else {
                    rawPtr = whisper_full_get_token_text_from_state(
                        ctx.ptr, state, Int32(s), Int32(t))
                }
                guard let rawPtr else {
                    continue
                }
                let token = String(cString: rawPtr)
                guard data.id >= 0, token.hasPrefix("[_") == false else { continue }

                accumulator.accept(
                    token: token,
                    start: TimeInterval(data.t0) / 100.0,
                    end: TimeInterval(data.t1) / 100.0
                )
            }

            words.append(contentsOf: accumulator.finish(segmentOffset: segmentOffset))
        }
        return words
    }

    internal static func invokeLogSuppressorsForTesting() {
        suppressLibraryLog(ggml_log_level(0), nil as UnsafePointer<CChar>?, nil)
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
