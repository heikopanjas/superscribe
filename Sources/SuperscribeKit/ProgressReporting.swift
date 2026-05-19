import Foundation

/// Shared progress throttling constants (~10 Hz).
public enum ProgressReporting {
    public static let throttleInterval: TimeInterval = 0.1
}

/// Builds `DownloadProgress` ticks for non-streaming install steps.
enum DownloadProgressReporting {
    static func emit(
        modelId: String,
        backend: Backend,
        currentFile: String,
        filesCompleted: Int,
        filesTotal: Int,
        bytesCompleted: Int64,
        bytesTotal: Int64?,
        onProgress: @Sendable (DownloadProgress) -> Void
    ) {
        onProgress(
            DownloadProgress(
                modelId: modelId,
                backend: backend,
                currentFile: currentFile,
                filesCompleted: filesCompleted,
                filesTotal: filesTotal,
                bytesCompleted: bytesCompleted,
                bytesTotal: bytesTotal,
                bytesPerSecond: nil
            )
        )
    }
}
