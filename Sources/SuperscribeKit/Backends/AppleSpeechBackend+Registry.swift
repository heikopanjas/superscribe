import Foundation

@available(macOS 26, *)
extension AppleSpeechBackend: ModelRegistry {
    public static let defaultModelId: String = AppleSpeechSupport.defaultLocaleId

    public static func installPath(for localeId: String) throws -> URL {
        return try AppleSpeechSupport.installMarkerURL(for: localeId)
    }

    public static func remoteModels() async throws -> [RemoteModelInfo] {
        let localeIds = await AppleSpeechLiveAPI.supportedLocaleIds()
        return try localeIds.map { id in
            RemoteModelInfo(
                id: id,
                repoId: AppleSpeechSupport.catalogRepoId,
                subpath: nil,
                totalSizeBytes: nil,
                fileCount: nil,
                lastModified: nil,
                repoURL: try AppleSpeechSupport.catalogRepoURL
            )
        }
    }

    public static func installedModels() async throws -> [InstalledModelInfo] {
        let installed = Set(await AppleSpeechLiveAPI.installedLocaleIds())
        let reserved = Set(await AppleSpeechLiveAPI.reservedLocaleIds())
        return try installed.union(reserved).sorted().map { id in
            let state: ModelInstallationState =
                if installed.contains(id) == true {
                    if reserved.contains(id) == true {
                        .installedAndReserved
                    }
                    else {
                        .installed
                    }
                }
                else { .reserved }
            return InstalledModelInfo(id: id, path: try Self.installPath(for: id), state: state)
        }
    }
}
