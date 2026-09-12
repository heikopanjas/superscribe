import Foundation

/// Shared Apple Speech helpers that do not import the Speech framework.
public enum AppleSpeechSupport {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var testForceRuntimeUnavailable = false
        var testOSMajorVersionOverride: Int?
        var testForceAPIAvailabilityFalse = false
        var testDefaultLocaleIdentifierOverride: String?
    }

    /// When `true`, `isRuntimeAvailable()` reports unavailable (for dispatch tests).
    internal static var testForceRuntimeUnavailable: Bool {
        get { return Self.testState[\.testForceRuntimeUnavailable] }
        set { Self.testState[\.testForceRuntimeUnavailable] = newValue }
    }
    /// Overrides `ProcessInfo` major version for availability tests.
    internal static var testOSMajorVersionOverride: Int? {
        get { return Self.testState[\.testOSMajorVersionOverride] }
        set { Self.testState[\.testOSMajorVersionOverride] = newValue }
    }
    /// When `true`, dispatch behaves as if the Speech API is unavailable at runtime.
    internal static var testForceAPIAvailabilityFalse: Bool {
        get { return Self.testState[\.testForceAPIAvailabilityFalse] }
        set { Self.testState[\.testForceAPIAvailabilityFalse] = newValue }
    }
    /// Overrides `Locale.current.identifier` for `defaultLocaleId` tests.
    internal static var testDefaultLocaleIdentifierOverride: String? {
        get { return Self.testState[\.testDefaultLocaleIdentifierOverride] }
        set { Self.testState[\.testDefaultLocaleIdentifierOverride] = newValue }
    }

    /// `true` on arm64 hosts running macOS 26 or later.
    public static func isRuntimeAvailable() -> Bool {
        if Self.testForceRuntimeUnavailable == true { return false }
        return Self.macOSMajorVersion() >= 26
    }

    internal static func macOSMajorVersion() -> Int {
        if let testOSMajorVersionOverride = Self.testOSMajorVersionOverride {
            return testOSMajorVersionOverride
        }
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// Default locale model id (BCP-47 style, e.g. `en-US`).
    public static var defaultLocaleId: String {
        let raw = Self.testDefaultLocaleIdentifierOverride ?? Locale.current.identifier
        if raw.isEmpty == true { return "en-US" }
        return Self.normalizeLocaleId(raw)
    }

    /// Normalizes CLI / config locale ids to a canonical BCP-47 form.
    public static func normalizeLocaleId(_ raw: String) -> String {
        return raw.replacingOccurrences(of: "_", with: "-")
    }

    /// Builds a `Locale` from a model id string.
    public static func locale(fromModelId modelId: String) -> Locale {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == true {
            return Locale(identifier: Self.defaultLocaleId.replacingOccurrences(of: "-", with: "_"))
        }
        return Locale(identifier: trimmed.replacingOccurrences(of: "-", with: "_"))
    }

    /// Sentinel URL for system-managed Speech locale assets (not a filesystem path).
    public static func installMarkerURL(for localeId: String) throws -> URL {
        let normalized = Self.normalizeLocaleId(localeId)
        try ModelPathValidation.identifier(normalized)
        return try HTTPURL.make(host: "locale", path: "/\(normalized)", scheme: "apple-speech")
    }

    /// Extracts the locale id from a sentinel install marker URL.
    public static func localeId(fromInstallMarker url: URL) -> String? {
        guard url.scheme == "apple-speech", url.host == "locale" else { return nil }
        let id = Self.normalizeLocaleId(url.lastPathComponent)
        return if id.isEmpty == true || id == "/" { nil }
        else { id }
    }

    public static func unavailableMessage() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return """
            Apple Speech requires macOS 26 or later \
            (current: macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion))
            """
    }

    public static let catalogRepoId = "Apple/Speech"
    public static var catalogRepoURL: URL {
        get throws { return try HTTPURL.make(host: "developer.apple.com", path: "/documentation/speech") }
    }
}

extension AppleSpeechSupport {
    /// Resolves the system default through supported locales, with a supported en-US fallback.
    public static func resolveModelId(_ requested: String? = nil) async throws -> String {
        guard Self.isRuntimeAvailable() == true else { throw BackendTranscriberError.unavailable(Self.unavailableMessage()) }
        if #available(macOS 26, *) {
            let operations = AppleSpeechAssetInstaller.operations ?? AppleSpeechLiveAPI.assetOperations
            let candidate = Self.locale(fromModelId: requested ?? Self.defaultLocaleId)
            if let locale = await operations.resolve(candidate) { return Self.normalizeLocaleId(locale.identifier) }
            if requested == nil, let fallback = await operations.resolve(Locale(identifier: "en-US")) { return Self.normalizeLocaleId(fallback.identifier) }
        }
        throw UnsupportedModelError(backend: .appleSpeech, model: requested ?? Self.defaultLocaleId)
    }
}
