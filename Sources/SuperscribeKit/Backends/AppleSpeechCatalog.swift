import Foundation

/// Availability-neutral catalog accessors used by `BackendDispatch`.
enum AppleSpeechCatalog {
    static var defaultModelId: String {
        return AppleSpeechSupport.defaultLocaleId
    }

    static func installPath(for localeId: String) throws -> URL {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else {
            throw ModelInstallationError.modelNotInstalled(model: localeId, backend: .appleSpeech)
        }
        return try AppleSpeechSupport.installMarkerURL(for: localeId)
    }

    static func remoteModels() async throws -> [RemoteModelInfo] {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else { return [] }
        if #available(macOS 26, *) {
            if AppleSpeechSupport.testForceAPIAvailabilityFalse == false {
                return try await AppleSpeechBackend.remoteModels()
            }
        }
        return []
    }

    static func installedModels() async throws -> [InstalledModelInfo] {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else { return [] }
        if #available(macOS 26, *) {
            if AppleSpeechSupport.testForceAPIAvailabilityFalse == false {
                return try await AppleSpeechBackend.installedModels()
            }
        }
        return []
    }
}
