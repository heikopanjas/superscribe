import Foundation

/// Shared Apple Speech helpers that do not import the Speech framework.
public enum AppleSpeechSupport {
    /// When `true`, `isRuntimeAvailable()` reports unavailable (for dispatch tests).
    nonisolated(unsafe) internal static var testForceRuntimeUnavailable = false
    /// Overrides `ProcessInfo` major version for availability tests.
    nonisolated(unsafe) internal static var testOSMajorVersionOverride: Int?
    /// When `true`, dispatch behaves as if the Speech API is unavailable at runtime.
    nonisolated(unsafe) internal static var testForceAPIAvailabilityFalse = false
    /// Overrides `Locale.current.identifier` for `defaultLocaleId` tests.
    nonisolated(unsafe) internal static var testDefaultLocaleIdentifierOverride: String?

    /// `true` on arm64 hosts running macOS 26 or later.
    public static func isRuntimeAvailable() -> Bool {
        if testForceRuntimeUnavailable == true { return false }
        return macOSMajorVersion() >= 26
    }

    internal static func macOSMajorVersion() -> Int {
        if let testOSMajorVersionOverride {
            return testOSMajorVersionOverride
        }
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// Default locale model id (BCP-47 style, e.g. `en-US`).
    public static var defaultLocaleId: String {
        let raw = testDefaultLocaleIdentifierOverride ?? Locale.current.identifier
        if raw.isEmpty == true { return "en-US" }
        return normalizeLocaleId(raw)
    }

    /// Normalizes CLI / config locale ids to a canonical BCP-47 form.
    public static func normalizeLocaleId(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-")
    }

    /// Builds a `Locale` from a model id string.
    public static func locale(fromModelId modelId: String) -> Locale {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == true {
            return Locale(identifier: defaultLocaleId.replacingOccurrences(of: "-", with: "_"))
        }
        return Locale(identifier: trimmed.replacingOccurrences(of: "-", with: "_"))
    }

    /// Sentinel URL for system-managed Speech locale assets (not a filesystem path).
    public static func installMarkerURL(for localeId: String) -> URL {
        let normalized = normalizeLocaleId(localeId)
        return URL(string: "apple-speech://locale/\(normalized)")!
    }

    /// Extracts the locale id from a sentinel install marker URL.
    public static func localeId(fromInstallMarker url: URL) -> String? {
        guard url.scheme == "apple-speech", url.host == "locale" else { return nil }
        let id = normalizeLocaleId(url.lastPathComponent)
        return id.isEmpty == true || id == "/" ? nil : id
    }

    public static func unavailableMessage() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return """
            Apple Speech requires macOS 26 or later \
            (current: macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion))
            """
    }

    public static let catalogRepoId = "Apple/Speech"
    public static let catalogRepoURL = URL(string: "https://developer.apple.com/documentation/speech")!
}
