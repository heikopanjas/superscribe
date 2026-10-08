import Foundation

extension ModelInstaller {
    /// Installs the speaker diarizer when missing, incomplete, or from older weights. Returns its directory.
    @discardableResult
    public static func installDiarizer(
        session: URLSession = .shared,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let finalDir = try DiarizerModel.installPath()
        return try await ModelLifecycleCoordinator.shared.withLock {
            if DiarizerModel.isInstalled(at: finalDir) == true { return finalDir }
            let info = try await HuggingFaceHub.repoInfo(repoId: DiarizerModel.repoId, session: session)
            let files = DiarizerModel.files(in: info.siblings)
            let model = RemoteModelInfo(
                id: DiarizerModel.id,
                repoId: DiarizerModel.repoId,
                totalSizeBytes: ModelDownloadFile.totalSize(of: files),
                fileCount: files.count,
                repoURL: try HTTPURL.make(host: "huggingface.co", path: "/\(DiarizerModel.repoId)")
            )
            try Self.preflightDiskSpace(requiredBytes: model.totalSizeBytes, installPath: finalDir)
            return try await Self.stageAndPublish(
                finalDir: finalDir,
                download: { stagingPath in
                    try await ModelDownloader.download(files: files, model: model, backend: nil, into: stagingPath, session: session, onProgress: onProgress)
                    try DiarizerModel.writeMarker(in: stagingPath)
                },
                validate: { DiarizerModel.isInstalled(at: $0) }
            )
        }
    }

    /// Removes the installed diarizer. Returns `false` when nothing was installed.
    @discardableResult
    public static func removeDiarizer() async throws -> Bool {
        let path = try DiarizerModel.installPath()
        return try await ModelLifecycleCoordinator.shared.withLock {
            guard FileManager.default.fileExists(atPath: path.path) == true else { return false }
            try FileManager.default.removeItem(at: path)
            return true
        }
    }
}
