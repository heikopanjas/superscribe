import Foundation

/// Static catalog interface implemented by each backend.
///
/// Listing the remote catalog or scanning the local install directory must
/// not require instantiating a backend or loading a model — hence all
/// requirements are static.
public protocol ModelRegistry {
    /// Built-in fall-back model id for this backend.
    static var defaultModelId: String { get }

    /// Fetches the live catalog of models from the backend's authoritative
    /// source (typically Hugging Face Hub).
    static func remoteModels() async throws -> [RemoteModelInfo]

    /// Enumerates the models that are currently installed on disk.
    static func installedModels() throws -> [InstalledModelInfo]
}
