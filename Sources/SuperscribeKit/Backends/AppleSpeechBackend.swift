import Foundation

/// Apple Speech (`SpeechAnalyzer` / `SpeechTranscriber`) backend for on-device
/// speech-to-text using system-managed locale assets.
@available(macOS 26, *)
public actor AppleSpeechBackend: Transcriber {
    /// Test hook for `ensureLoaded()` without Speech assets on disk.
    nonisolated(unsafe) internal static var testLoadHook: (@Sendable () async throws -> AppleSpeechSession)?
    /// When `true`, `isAvailable` reports unavailable (for dispatch tests).
    nonisolated(unsafe) internal static var testForceUnavailable = false

    public nonisolated static var isAvailable: Bool {
        if testForceUnavailable == true { return false }
        return AppleSpeechSupport.isRuntimeAvailable()
    }

    struct AppleSpeechSession: Sendable {
        let locale: Locale
        let localeId: String
    }

    private let loader = LoadOnce<AppleSpeechSession>()
    private let localeId: String

    public init(model: String = AppleSpeechBackend.defaultModelId) {
        self.localeId = AppleSpeechSupport.normalizeLocaleId(model)
    }

    public nonisolated var capabilities: BackendCapabilities {
        BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Apple Speech",
            defaultModelId: AppleSpeechBackend.defaultModelId
        )
    }

    public func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        let session = try await ensureLoaded()
        let spans = try await AppleSpeechLiveAPI.transcribe(
            samples: samples,
            locale: session.locale,
            prompt: config.prompt
        )
        let words = AppleSpeechResultMapping.map(spans: spans, segmentOffset: segment.start)
        return SegmentTranscription(segment: segment, words: words)
    }

    private func ensureLoaded() async throws -> AppleSpeechSession {
        try await loader.get { [localeId] in
            if let hook = Self.testLoadHook {
                return try await hook()
            }
            guard await AppleSpeechLiveAPI.isLocaleInstalled(localeId) == true else {
                throw ModelInstallationError.modelNotInstalled(model: localeId, backend: .appleSpeech)
            }
            let locale = AppleSpeechSupport.locale(fromModelId: localeId)
            guard await AppleSpeechLiveAPI.resolveSupportedLocale(for: locale) != nil else {
                throw AppleSpeechError.localeUnsupported(localeId)
            }
            return AppleSpeechSession(locale: locale, localeId: localeId)
        }
    }
}
