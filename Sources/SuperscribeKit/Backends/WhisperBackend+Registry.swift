import Foundation

extension WhisperBackend: ModelRegistry {
    public static let defaultModelId = "large-v3-turbo"

    /// Hugging Face repo that hosts the GGML model `.bin` files.
    public static let huggingFaceRepoId = "ggerganov/whisper.cpp"

    public static func remoteModels() async throws -> [RemoteModelInfo] {
        let info = try await HuggingFaceHub.repoInfo(repoId: huggingFaceRepoId)
        return filterGGMLSiblings(info.siblings, lastModified: info.lastModified)
    }

    /// On-disk location for an installed Whisper GGML model.
    /// Single `.bin` file under our own cache root.
    public static func installPath(for modelId: String) -> URL {
        whisperCacheDirectory().appendingPathComponent("\(modelId).bin")
    }

    public static func installedModels() throws -> [InstalledModelInfo] {
        let dir = whisperCacheDirectory()
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return
            entries
            .filter { $0.hasSuffix(".bin") }
            .map { filename -> InstalledModelInfo in
                let id = String(filename.dropLast(4))  // drop ".bin"
                let path = dir.appendingPathComponent(filename)
                let size = (try? path.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                return InstalledModelInfo(id: id, path: path, sizeBytes: size.map(Int64.init))
            }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Pure helpers (testable)

    /// Filter HF repo siblings to those matching `ggml-<id>.bin` at the root
    /// of the repo (no subdirectory). The capture group becomes the model id.
    public static func filterGGMLSiblings(
        _ siblings: [HuggingFaceHub.HFSibling],
        lastModified: Date? = nil
    ) -> [RemoteModelInfo] {
        let repoURL = URL(string: "https://huggingface.co/\(huggingFaceRepoId)")!
        return siblings.compactMap { sibling in
            // Match exactly: "ggml-<id>.bin" with no path separator.
            guard !sibling.rfilename.contains("/"),
                sibling.rfilename.hasPrefix("ggml-"),
                sibling.rfilename.hasSuffix(".bin")
            else { return nil }
            let id = String(
                sibling.rfilename
                    .dropFirst("ggml-".count)
                    .dropLast(".bin".count)
            )
            guard !id.isEmpty else { return nil }
            return RemoteModelInfo(
                id: id,
                repoId: huggingFaceRepoId,
                subpath: nil,
                totalSizeBytes: sibling.size,
                fileCount: 1,
                lastModified: lastModified,
                repoURL: repoURL
            )
        }
        .sorted { $0.id < $1.id }
    }

    // MARK: - Private

    static func whisperCacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("superscribe/whisper", isDirectory: true)
    }
}
