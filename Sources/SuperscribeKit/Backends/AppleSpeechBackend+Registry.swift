import Foundation

@available(macOS 26, *)
extension AppleSpeechBackend {
    public static let defaultModelId: String = AppleSpeechSupport.defaultLocaleId

    public static func installPath(for localeId: String) -> URL {
        AppleSpeechSupport.installMarkerURL(for: localeId)
    }

    public static func remoteModels() async throws -> [RemoteModelInfo] {
        let localeIds = await AppleSpeechLiveAPI.supportedLocaleIds()
        return localeIds.map { id in
            RemoteModelInfo(
                id: id,
                repoId: AppleSpeechSupport.catalogRepoId,
                subpath: nil,
                totalSizeBytes: nil,
                fileCount: nil,
                lastModified: nil,
                repoURL: AppleSpeechSupport.catalogRepoURL
            )
        }
    }

    public static func installedModels() async throws -> [InstalledModelInfo] {
        let localeIds = await AppleSpeechLiveAPI.installedLocaleIds()
        return localeIds.map { id in
            InstalledModelInfo(
                id: id,
                path: installPath(for: id),
                sizeBytes: nil
            )
        }
    }
}

/// Availability-neutral catalog accessors used by `BackendDispatch`.
enum AppleSpeechCatalog {
    static var defaultModelId: String {
        AppleSpeechSupport.defaultLocaleId
    }

    static func installPath(for localeId: String) throws -> URL {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else {
            throw ModelInstallationError.modelNotInstalled(model: localeId, backend: .appleSpeech)
        }
        return AppleSpeechSupport.installMarkerURL(for: localeId)
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
