import Foundation
import whisper

/// Sendable box for a C `OpaquePointer` (whisper_context *).
/// whisper_context is not thread-safe for writes, but we only read from it
/// (via per-call whisper_state), so the isolation is safe.
private final class WhisperContext: @unchecked Sendable {
    let ptr: OpaquePointer
    private let manageLifetime: Bool

    init(_ ptr: OpaquePointer, manageLifetime: Bool = true) {
        self.ptr = ptr
        self.manageLifetime = manageLifetime
    }

    /// Unit-test placeholder; never passed to whisper C API release functions.
    static func testStub() -> WhisperContext {
        WhisperContext(OpaquePointer(bitPattern: 0x1)!, manageLifetime: false)
    }

    deinit {
        if manageLifetime == true {
            WhisperLiveAPI.releaseContext(ptr)
        }
    }
}

/// Synthetic whisper token for unit tests (avoids on-disk GGML models).
internal struct WhisperTestToken: Sendable {
    let token: String
    let id: Int32
    let t0: Int64
    let t1: Int64
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
    /// When `true`, `ensureLoaded` returns a stub context (no `.bin` on disk).
    nonisolated(unsafe) internal static var testUseStubLoad = false
    /// When set for `stub-*` model ids, simulates whisper token API results.
    nonisolated(unsafe) internal static var testWhisperAPISegments: [[WhisperTestToken]]?
    /// When set for `stub-*` model ids, bypasses `whisper_init_from_file_with_params`.
    nonisolated(unsafe) internal static var testWhisperInitPointer: OpaquePointer?
    /// When set for `stub-*` model ids, bypasses `whisper_init_state`.
    nonisolated(unsafe) internal static var testWhisperStatePointer: OpaquePointer?

    internal static func isStubModel(_ modelId: String) -> Bool {
        modelId.hasPrefix("stub-")
    }

    private static func shouldUseStubLoad(for modelId: String) -> Bool {
        testUseStubLoad == true && isStubModel(modelId)
    }

    private static func shouldUseStubAPI(for modelId: String) -> Bool {
        testWhisperAPISegments != nil && isStubModel(modelId)
    }

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

        let useStubAPI = Self.shouldUseStubAPI(for: modelId)

        let state: OpaquePointer?
        if Self.testForceStateInitFailed == true {
            state = nil
        }
        else {
            state = WhisperLiveAPI.initState(context: context.ptr, modelId: modelId)
        }
        guard let state else {
            throw WhisperError.stateInitFailed
        }
        defer {
            WhisperLiveAPI.releaseState(state, modelId: modelId, usedStubAPI: useStubAPI)
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.token_timestamps = true
        params.temperature_inc = 0.0

        let languageCStr: [CChar]? = config.language.flatMap { $0.cString(using: .utf8) }
        if languageCStr != nil {
            params.language = languageCStr!.withUnsafeBufferPointer { $0.baseAddress }
        }

        let promptCStr: [CChar]? = config.prompt.flatMap { $0.cString(using: .utf8) }
        if promptCStr != nil {
            params.initial_prompt = promptCStr!.withUnsafeBufferPointer { $0.baseAddress }
        }

        let rc = WhisperLiveAPI.runFull(
            context: context.ptr,
            state: state,
            params: params,
            samples: samples,
            useStubAPI: useStubAPI
        )
        guard rc == 0 else {
            throw WhisperError.transcriptionFailed(code: rc)
        }

        let words = extractTimedWords(
            ctx: context,
            state: state,
            segmentOffset: segment.start,
            modelId: modelId
        )
        return SegmentTranscription(segment: segment, words: words)
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> WhisperContext {
        try await loader.get { [modelId] in
            if Self.shouldUseStubLoad(for: modelId) == true {
                return WhisperContext.testStub()
            }
            let binURL = WhisperBackend.installPath(for: modelId)
            try ModelInstallSupport.requireInstalled(
                at: binURL, modelId: modelId, backend: .whisperCpp
            )
            let binPath = binURL.path
            FileHandle.standardError.write(
                Data("Loading Whisper model \(modelId)...\n".utf8)
            )
            return try Self.loadWhisperContext(from: binPath, modelId: modelId)
        }
    }

    private static func loadWhisperContext(from binPath: String, modelId: String) throws -> WhisperContext {
        var ctxParams = whisper_context_default_params()
        ctxParams.use_gpu = true
        ctxParams.flash_attn = true
        ggml_log_set(suppressLibraryLog, nil)
        whisper_log_set(suppressLibraryLog, nil)

        let ptr: OpaquePointer?
        if isStubModel(modelId), let injected = testWhisperInitPointer {
            ptr = injected
        }
        else {
            ptr = WhisperLiveAPI.initContext(from: binPath, ctxParams: ctxParams)
        }
        guard let ptr else {
            throw WhisperError.contextInitFailed(path: binPath)
        }
        let manageLifetime = isStubModel(modelId) == false || testWhisperInitPointer == nil
        return WhisperContext(ptr, manageLifetime: manageLifetime)
    }

    private nonisolated func extractTimedWords(
        ctx: WhisperContext,
        state: OpaquePointer,
        segmentOffset: TimeInterval,
        modelId: String
    ) -> [TimedWord] {
        var words: [TimedWord] = []
        let nSegments = WhisperLiveAPI.segmentCount(from: state, modelId: modelId)

        for s in 0 ..< nSegments {
            let nTokens = WhisperLiveAPI.tokenCount(from: state, segment: s, modelId: modelId)
            var accumulator = TokenAccumulator()

            for t in 0 ..< nTokens {
                let data = WhisperLiveAPI.tokenData(from: state, segment: s, token: t, modelId: modelId)
                let tokenText = WhisperLiveAPI.tokenText(
                    context: ctx.ptr,
                    state: state,
                    segment: s,
                    token: t,
                    modelId: modelId
                )
                guard let tokenText else {
                    continue
                }
                guard data.id >= 0, tokenText.hasPrefix("[_") == false else { continue }

                accumulator.accept(
                    token: tokenText,
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

    /// Exercises managed `WhisperContext` deinit without a real GGML model.
    internal static func exerciseManagedContextReleaseForTesting() {
        WhisperLiveAPI.testSkipContextRelease = true
        defer { WhisperLiveAPI.testSkipContextRelease = false }
        autoreleasepool {
            _ = WhisperContext(OpaquePointer(bitPattern: 0x10)!, manageLifetime: true)
        }
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
