import Darwin
import Foundation

/// Snapshot of an in-progress model download.
public struct DownloadProgress: Sendable, Hashable {
    public let modelId: String
    public let backend: Backend
    public let currentFile: String
    public let filesCompleted: Int
    public let filesTotal: Int
    public let bytesCompleted: Int64
    public let bytesTotal: Int64?
    public let bytesPerSecond: Double?

    public init(
        modelId: String,
        backend: Backend,
        currentFile: String,
        filesCompleted: Int,
        filesTotal: Int,
        bytesCompleted: Int64,
        bytesTotal: Int64?,
        bytesPerSecond: Double?
    ) {
        self.modelId = modelId
        self.backend = backend
        self.currentFile = currentFile
        self.filesCompleted = filesCompleted
        self.filesTotal = filesTotal
        self.bytesCompleted = bytesCompleted
        self.bytesTotal = bytesTotal
        self.bytesPerSecond = bytesPerSecond
    }

    /// 0…1, or `nil` if total is unknown.
    public var fraction: Double? {
        guard let total = self.bytesTotal, total > 0 else { return nil }
        return min(1, Double(self.bytesCompleted) / Double(total))
    }
}
