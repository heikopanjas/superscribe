import Foundation

/// Apple Speech (`SpeechAnalyzer` / `SpeechTranscriber`) backend for on-device
/// speech-to-text using system-managed locale assets.
@available(macOS 26, *)
public actor AppleSpeechBackend: Transcriber {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var testLoadHook: (@Sendable () async throws -> AppleSpeechSession)?
        var testForceUnavailable = false
    }

    /// Test hook for `ensureLoaded()` without Speech assets on disk.
    internal static var testLoadHook: (@Sendable () async throws -> AppleSpeechSession)? {
        get { return Self.testState[\.testLoadHook] }
        set { Self.testState[\.testLoadHook] = newValue }
    }
    /// When `true`, `isAvailable` reports unavailable (for dispatch tests).
    internal static var testForceUnavailable: Bool {
        get { return Self.testState[\.testForceUnavailable] }
        set { Self.testState[\.testForceUnavailable] = newValue }
    }

    public nonisolated static var isAvailable: Bool {
        if Self.testForceUnavailable == true { return false }
        return AppleSpeechSupport.isRuntimeAvailable()
    }

    struct AppleSpeechSession: Sendable {
        let locale: Locale
        let localeId: String
    }

    private let loader = LoadOnce<AppleSpeechSession>()
    private let localeId: String
    private let requestedLocaleId: String?
    private var resolvedLocaleId: String?
    public var modelId: String { return self.resolvedLocaleId ?? self.localeId }

    public init(model: String? = nil) throws {
        if let model { try ModelPathValidation.identifier(model) }
        self.requestedLocaleId = model
        self.localeId = AppleSpeechSupport.normalizeLocaleId(model ?? AppleSpeechSupport.defaultLocaleId)
    }

    public nonisolated var capabilities: BackendCapabilities {
        return BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Apple Speech",
            defaultModelId: Self.defaultModelId
        )
    }

    public func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        try config.validate()
        let session = try await self.ensureLoaded()
        self.resolvedLocaleId = session.localeId
        let spans = try await AppleSpeechLiveAPI.transcribe(
            samples: samples,
            locale: session.locale,
            prompt: config.prompt
        )
        let words = AppleSpeechResultMapping.map(spans: spans, segmentOffset: segment.start)
        return SegmentTranscription(segment: segment, words: words)
    }

    private func ensureLoaded() async throws -> AppleSpeechSession {
        return try await self.loader.get { [requestedLocaleId = self.requestedLocaleId] in
            if let hook = Self.testLoadHook {
                return try await hook()
            }
            let canonicalId = try await AppleSpeechSupport.resolveModelId(requestedLocaleId)
            let locale = AppleSpeechSupport.locale(fromModelId: canonicalId)
            guard await AppleSpeechLiveAPI.isLocaleInstalled(canonicalId) == true else {
                throw ModelInstallationError.modelNotInstalled(model: canonicalId, backend: .appleSpeech)
            }
            return AppleSpeechSession(locale: locale, localeId: canonicalId)
        }
    }
}
