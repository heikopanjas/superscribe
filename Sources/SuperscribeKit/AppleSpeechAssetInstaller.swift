import Foundation

/// Installs and releases Apple Speech locale assets via `AssetInventory`.
public enum AppleSpeechAssetInstaller {
    @TaskLocal internal static var operations: AppleSpeechAssetOperations?

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
                let operations = Self.operations ?? AppleSpeechLiveAPI.assetOperations
                return try await Self.install(localeId: localeId, backend: backend, operations: operations, onProgress: onProgress)
            }
        }
        throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
    }

    internal static func install(
        localeId: String,
        backend: Backend,
        operations: AppleSpeechAssetOperations,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        let requested = AppleSpeechSupport.locale(fromModelId: localeId)
        guard let locale = await operations.resolve(requested) else {
            throw AppleSpeechError.localeUnsupported(AppleSpeechSupport.normalizeLocaleId(localeId))
        }
        try Task.checkCancellation()
        let acquired = try await operations.reserve(locale)
        do {
            try Task.checkCancellation()
            let modelId = AppleSpeechSupport.normalizeLocaleId(locale.identifier)
            if let installation = try await operations.installation(locale) {
                try await installation.run(modelId: modelId, backend: backend, onProgress: onProgress)
            }
            try Task.checkCancellation()
            return try AppleSpeechSupport.installMarkerURL(for: modelId)
        }
        catch {
            if acquired == true {
                await operations.release(locale)
            }
            throw error
        }
    }

    public static func release(localeId: String) async -> Void {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else { return }
        if #available(macOS 26, *) {
            let requested = AppleSpeechSupport.locale(fromModelId: localeId)
            let operations = Self.operations ?? AppleSpeechLiveAPI.assetOperations
            let locale = await operations.resolve(requested) ?? requested
            await operations.release(locale)
        }
    }
}
