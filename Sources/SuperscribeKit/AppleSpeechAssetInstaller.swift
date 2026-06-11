import Foundation

/// Installs and releases Apple Speech locale assets via `AssetInventory`.
public enum AppleSpeechAssetInstaller {
    public static func isInstalled(localeId: String) async -> Bool {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else { return false }
        if #available(macOS 26, *) {
            if AppleSpeechSupport.testForceAPIAvailabilityFalse == false {
                return await AppleSpeechLiveAPI.isLocaleInstalled(localeId)
            }
        }
        return false
    }

    public static func ensureInstalled(
        localeId: String,
        backend: Backend,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else {
            throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
        }
        if #available(macOS 26, *) {
            if AppleSpeechSupport.testForceAPIAvailabilityFalse == false {
                let locale = AppleSpeechSupport.locale(fromModelId: localeId)
                guard await AppleSpeechLiveAPI.resolveSupportedLocale(for: locale) != nil else {
                    throw AppleSpeechError.localeUnsupported(AppleSpeechSupport.normalizeLocaleId(localeId))
                }
                try await AppleSpeechLiveAPI.ensureLocaleInstalled(
                    locale: locale,
                    modelId: AppleSpeechSupport.normalizeLocaleId(localeId),
                    backend: backend,
                    onProgress: onProgress
                )
                return AppleSpeechSupport.installMarkerURL(for: localeId)
            }
        }
        throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
    }

    public static func release(localeId: String) async {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else { return }
        if #available(macOS 26, *) {
            let locale = AppleSpeechSupport.locale(fromModelId: localeId)
            await AppleSpeechLiveAPI.releaseLocale(locale)
        }
    }
}
