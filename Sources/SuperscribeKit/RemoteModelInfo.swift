import Foundation

// MARK: - Model info

/// Describes a model published in a remote catalog (Hugging Face Hub).
public struct RemoteModelInfo: Sendable, Codable, Hashable {
    /// Short identifier the user passes to `--model` (e.g. `"v3"`,
    /// `"large-v3_turbo"`). May be a passed-through repo name when no
    /// short alias is known.
    public let id: String
    /// Hugging Face repo id (e.g. `"ggerganov/whisper.cpp"`).
    public let repoId: String
    /// Total size in bytes across all files of the model, when known.
    public let totalSizeBytes: Int64?
    /// Number of files comprising the model, when known.
    public let fileCount: Int?
    /// Last-modified timestamp of the source repo, when known.
    public let lastModified: Date?
    /// Canonical URL to the model on Hugging Face.
    public let repoURL: URL

    public init(
        id: String,
        repoId: String,
        totalSizeBytes: Int64? = nil,
        fileCount: Int? = nil,
        lastModified: Date? = nil,
        repoURL: URL
    ) {
        self.id = id
        self.repoId = repoId
        self.totalSizeBytes = totalSizeBytes
        self.fileCount = fileCount
        self.lastModified = lastModified
        self.repoURL = repoURL
    }
}
