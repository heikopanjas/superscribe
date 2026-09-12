import Foundation

/// Owns installation and progress collection until both have stopped.
internal struct AppleSpeechInstallation: Sendable {
    internal let progress: Progress
    internal let download: @Sendable () async throws -> Void

    internal func run(modelId: String, backend: Backend, onProgress: @Sendable @escaping (DownloadProgress) -> Void) async throws -> Void {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.download()
            }
            group.addTask {
                while Task.isCancelled == false {
                    onProgress(
                        DownloadProgress(
                            modelId: modelId,
                            backend: backend,
                            currentFile: modelId,
                            filesCompleted: 0,
                            filesTotal: 1,
                            bytesCompleted: self.progress.completedUnitCount,
                            bytesTotal: self.progress.totalUnitCount > 0 ? self.progress.totalUnitCount : nil,
                            bytesPerSecond: nil
                        ))
                    try? await Task.sleep(for: .seconds(ProgressReporting.throttleInterval))
                }
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
}
