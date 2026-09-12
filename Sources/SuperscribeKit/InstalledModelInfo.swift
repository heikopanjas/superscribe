import Foundation

/// Describes a model that is currently installed on disk for a backend.
public struct InstalledModelInfo: Sendable, Codable, Hashable {
    /// Short identifier the user passes to `--model`.
    public let id: String
    /// Filesystem location of the installed model.
    public let path: URL
    /// Total size in bytes on disk, when computable.
    public let sizeBytes: Int64?
    public let state: ModelInstallationState

    public init(id: String, path: URL, sizeBytes: Int64? = nil, state: ModelInstallationState = .installed) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
        self.state = state
    }
}
