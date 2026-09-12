import Foundation
import whisper

private func suppressLibraryLog(
    _ level: ggml_log_level,
    _ text: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) -> Void {}

/// whisper.cpp backend for on-device speech-to-text using OpenAI Whisper GGML
/// models. Encoder runs on the Apple Neural Engine when a Core ML bundle is
/// installed beside the `.bin`; otherwise Metal GPU. Decoder uses Metal.
///
/// Each instance owns a single `whisper_context` loaded from a `.bin` model
/// file on disk. An owned serial worker performs initialization, inference,
/// and destruction. Cancellation is bridged into whisper's abort callback.
public actor WhisperBackend: Transcriber {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var testForceUnavailable = false
        var testForceStateInitFailed = false
        var testForceTranscriptionFailed = false
        var testForceNilTokenText = false
        var testNilTokenTextSkipsRemaining = 0
        var testUseStubLoad = false
        var testWhisperAPISegments: [[WhisperTestToken]]?
        var testWhisperInitPointer: OpaquePointer?
        var testWhisperStatePointer: OpaquePointer?
        var overrideRemoteModelsSession: URLSession?
        var defaultRemoteModelsSession: URLSession = .shared
    }

    /// When `true`, `isAvailable` reports unavailable (for dispatch tests).
    internal static var testForceUnavailable: Bool {
        get { return Self.testState[\.testForceUnavailable] }
        set { Self.testState[\.testForceUnavailable] = newValue }
    }
    /// When `true`, `transcribe` throws `stateInitFailed` after load.
    internal static var testForceStateInitFailed: Bool {
        get { return Self.testState[\.testForceStateInitFailed] }
        set { Self.testState[\.testForceStateInitFailed] = newValue }
    }
    /// When `true`, `transcribe` throws `transcriptionFailed`.
    internal static var testForceTranscriptionFailed: Bool {
        get { return Self.testState[\.testForceTranscriptionFailed] }
        set { Self.testState[\.testForceTranscriptionFailed] = newValue }
    }
    /// When `true`, `extractTimedWords` skips tokens whose text pointer is nil.
    internal static var testForceNilTokenText: Bool {
        get { return Self.testState[\.testForceNilTokenText] }
        set { Self.testState[\.testForceNilTokenText] = newValue }
    }
    internal static var testNilTokenTextSkipsRemaining: Int {
        get { return Self.testState[\.testNilTokenTextSkipsRemaining] }
        set { Self.testState[\.testNilTokenTextSkipsRemaining] = newValue }
    }
    /// When `true`, `ensureLoaded` returns a stub context (no `.bin` on disk).
    internal static var testUseStubLoad: Bool {
        get { return Self.testState[\.testUseStubLoad] }
        set { Self.testState[\.testUseStubLoad] = newValue }
    }
    /// When set for `stub-*` model ids, simulates whisper token API results.
    internal static var testWhisperAPISegments: [[WhisperTestToken]]? {
        get { return Self.testState[\.testWhisperAPISegments] }
        set { Self.testState[\.testWhisperAPISegments] = newValue }
    }
    /// When set for `stub-*` model ids, bypasses `whisper_init_from_file_with_params`.
    internal static var testWhisperInitPointer: OpaquePointer? {
        get { return Self.testState[\.testWhisperInitPointer] }
        set { Self.testState[\.testWhisperInitPointer] = newValue }
    }
    /// When set for `stub-*` model ids, bypasses `whisper_init_state`.
    internal static var testWhisperStatePointer: OpaquePointer? {
        get { return Self.testState[\.testWhisperStatePointer] }
        set { Self.testState[\.testWhisperStatePointer] = newValue }
    }

    internal static func isStubModel(_ modelId: String) -> Bool {
        return modelId.hasPrefix("stub-")
    }

    private static func shouldUseStubLoad(for modelId: String) -> Bool {
        return Self.testUseStubLoad == true && Self.isStubModel(modelId)
    }

    private static func shouldUseStubAPI(for modelId: String) -> Bool {
        return Self.testWhisperAPISegments != nil && Self.isStubModel(modelId)
    }

    public nonisolated static var isAvailable: Bool {
        if Self.testForceUnavailable == true { return false }
        return true
    }

    // Static initialization registers process-global C callbacks once, before any context starts.
    private static let logSuppression: Void = {
        ggml_log_set(suppressLibraryLog, nil)
        whisper_log_set(suppressLibraryLog, nil)
    }()

    private let worker = BlockingWorker(label: "superscribe.whisper")
    private let loader = LoadOnce<WhisperContext>()
    public nonisolated let modelId: String

    /// - Throws: An error if the model identifier is invalid.
    /// - Parameter model: GGML model variant, e.g. `"large-v3-turbo"`, `"base"`,
    ///   `"medium-q5_0"`. Defaults to `"large-v3-turbo"`.
    public init(model: String = WhisperBackend.defaultModelId) throws {
        try ModelPathValidation.identifier(model)
        self.modelId = model
    }

    public nonisolated var capabilities: BackendCapabilities {
        return BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Whisper (whisper.cpp)",
            defaultModelId: Self.defaultModelId
        )
    }

    // MARK: - Transcriber

    public func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        try config.validate()
        if let language = config.language, language != "auto" {
            guard language.withCString({ whisper_lang_id($0) }) >= 0 else {
                throw WhisperError.unsupportedLanguage(language)
            }
        }
        let context = try await self.ensureLoaded()
        let dependencies = Self.testState
        let liveDependencies = WhisperLiveAPI.testState
        let invocation = WhisperLiveAPI.invocation
        return try await self.worker.run { [modelId = self.modelId] cancellation in
            return try Self.$testState.withValue(dependencies) {
                return try WhisperLiveAPI.$testState.withValue(liveDependencies) {
                    return try WhisperLiveAPI.$invocation.withValue(invocation) {
                        return try Self.infer(context: context, modelId: modelId, samples: samples, segment: segment, config: config, cancellation: cancellation)
                    }
                }
            }
        }
    }

    private static func infer(
        context: WhisperContext, modelId: String, samples: [Float], segment: SpeechSegment, config: TranscriptionConfig, cancellation: CancellationFlag
    ) throws -> SegmentTranscription {
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

        var input = samples
        let padded = samples.isEmpty == false && samples.count < 16_000
        if padded == true {
            input.append(contentsOf: repeatElement(0, count: 16_000 - input.count))
        }
        params.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<CancellationFlag>.fromOpaque(userData).takeUnretainedValue().isCancelled
        }
        params.abort_callback_user_data = Unmanaged.passUnretained(cancellation).toOpaque()
        let rc = CStringScope.withCString(config.language) { language in
            return CStringScope.withCString(config.prompt) { prompt in
                params.language = language
                params.initial_prompt = prompt
                return WhisperLiveAPI.runFull(
                    context: context.ptr,
                    state: state,
                    params: params,
                    samples: input,
                    useStubAPI: useStubAPI
                )
            }
        }
        try cancellation.check()
        guard rc == 0 else {
            throw WhisperError.transcriptionFailed(code: rc)
        }

        let words = Self.extractTimedWords(
            ctx: context,
            state: state,
            segmentOffset: segment.start,
            modelId: modelId
        )
        if padded == true {
            let bounded = words.compactMap { word -> TimedWord? in
                if word.start >= segment.end { return nil }
                return TimedWord(text: word.text, start: word.start, end: min(word.end, segment.end))
            }
            return SegmentTranscription(segment: segment, words: bounded)
        }
        return SegmentTranscription(segment: segment, words: words)
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> WhisperContext {
        return try await self.loader.get { [modelId = self.modelId, worker = self.worker] in
            if Self.shouldUseStubLoad(for: modelId) == true {
                return WhisperContext.testStub(worker: worker)
            }
            let binURL = Self.installPath(for: modelId)
            try ModelInstallSupport.requireInstalled(
                at: binURL, modelId: modelId, backend: .whisperCpp
            )
            let binPath = binURL.path
            FileHandle.standardError.write(
                Data("Loading Whisper model \(modelId)...\n".utf8)
            )
            let dependencies = Self.testState
            let liveDependencies = WhisperLiveAPI.testState
            return try await worker.run { _ in
                return try Self.$testState.withValue(dependencies) {
                    return try WhisperLiveAPI.$testState.withValue(liveDependencies) {
                        return try Self.loadWhisperContext(from: binPath, modelId: modelId, worker: worker)
                    }
                }
            }
        }
    }

    private static func loadWhisperContext(from binPath: String, modelId: String, worker: BlockingWorker) throws -> WhisperContext {
        var ctxParams = whisper_context_default_params()
        ctxParams.use_gpu = true
        ctxParams.flash_attn = true
        _ = Self.logSuppression

        let ptr: OpaquePointer?
        if (Self.isStubModel(modelId)) == true, let injected = Self.testWhisperInitPointer {
            ptr = injected
        }
        else {
            ptr = WhisperLiveAPI.initContext(from: binPath, ctxParams: ctxParams)
        }
        guard let ptr else {
            throw WhisperError.contextInitFailed(path: binPath)
        }
        let manageLifetime = Self.isStubModel(modelId) == false || Self.testWhisperInitPointer == nil
        return WhisperContext(ptr, worker: worker, manageLifetime: manageLifetime)
    }

    private static func extractTimedWords(
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

    internal static func invokeLogSuppressorsForTesting() -> Void {
        suppressLibraryLog(ggml_log_level(0), nil as UnsafePointer<CChar>?, nil)
    }

    /// Exercises managed `WhisperContext` deinit without a real GGML model.
    internal static func exerciseManagedContextReleaseForTesting() -> Void {
        WhisperLiveAPI.testSkipContextRelease = true
        defer { WhisperLiveAPI.testSkipContextRelease = false }
        autoreleasepool {
            let worker = BlockingWorker(label: "superscribe.whisper.test")
            _ = WhisperContext(OpaquePointer(Unmanaged.passUnretained(worker).toOpaque()), worker: worker, manageLifetime: true)
        }
    }
}
