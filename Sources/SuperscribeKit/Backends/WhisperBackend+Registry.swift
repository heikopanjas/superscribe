import Foundation

extension WhisperBackend: ModelRegistry {
    public static let defaultModelId = "large-v3-turbo"

    /// Hugging Face repo that hosts the GGML model `.bin` files.
    public static let huggingFaceRepoId = "ggerganov/whisper.cpp"

    public static func remoteModels() async throws -> [RemoteModelInfo] {
        try await remoteModels(session: overrideRemoteModelsSession ?? defaultRemoteModelsSession)
    }

    /// Override for unit tests; nil uses `defaultRemoteModelsSession`.
    nonisolated(unsafe) static var overrideRemoteModelsSession: URLSession?
    /// Default session when `overrideRemoteModelsSession` is nil (`.shared` in production).
    nonisolated(unsafe) static var defaultRemoteModelsSession: URLSession = .shared

    static func remoteModels(session: URLSession) async throws -> [RemoteModelInfo] {
        let info = try await HuggingFaceHub.repoInfo(repoId: huggingFaceRepoId, session: session)
        return filterGGMLSiblings(info.siblings, lastModified: info.lastModified)
    }

    /// On-disk location for an installed Whisper GGML model.
    /// Single `.bin` file under our own cache root.
    public static func installPath(for modelId: String) -> URL {
        whisperCacheDirectory().appendingPathComponent("\(modelId).bin")
    }

    public static func installedModels() throws -> [InstalledModelInfo] {
        let dir = whisperCacheDirectory()
        guard FileManager.default.fileExists(atPath: dir.path) == true else { return [] }
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
            .sortedById()
    }

    /// Directory whisper.cpp loads for ANE encoder inference (`{base}-encoder.mlmodelc`).
    public static func encoderInstallPath(for modelId: String) -> URL {
        whisperCacheDirectory().appendingPathComponent(
            "\(encoderBaseId(for: modelId))-encoder.mlmodelc",
            isDirectory: true
        )
    }

    /// Base model name used for Core ML encoder artifacts (strips quant suffixes).
    public static func encoderBaseId(for modelId: String) -> String {
        guard modelId.count >= 5 else { return modelId }
        let suffix = modelId.suffix(5)
        // Match whisper.cpp: -q?_? (e.g. -q5_0, -q8_0)
        if suffix.first == "-",
            suffix.dropFirst().first == "q",
            suffix.dropFirst(3).first == "_"
        {
            return String(modelId.dropLast(5))
        }
        return modelId
    }

    /// HF repo filename for the encoder zip (`ggml-<base>-encoder.mlmodelc.zip`).
    public static func encoderZipRemoteName(for modelId: String) -> String {
        "ggml-\(encoderBaseId(for: modelId))-encoder.mlmodelc.zip"
    }

    /// Finds the encoder zip sibling for `modelId`, if published on the repo.
    public static func encoderZipSibling(
        for modelId: String,
        in siblings: [HuggingFaceHub.HFSibling]
    ) -> HuggingFaceHub.HFSibling? {
        let name = encoderZipRemoteName(for: modelId)
        return siblings.first { $0.rfilename == name }
    }

    /// `true` when the Core ML encoder bundle directory exists.
    public static func isEncoderInstalled(modelId: String) -> Bool {
        SuperscribeFS.isExistingDirectory(at: encoderInstallPath(for: modelId))
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
            guard sibling.rfilename.contains("/") == false,
                sibling.rfilename.hasPrefix("ggml-") == true,
                sibling.rfilename.hasSuffix(".bin") == true
            else { return nil }
            let id = String(
                sibling.rfilename
                    .dropFirst("ggml-".count)
                    .dropLast(".bin".count)
            )
            guard id.isEmpty == false else { return nil }
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
        .sortedById()
    }

    // MARK: - Private

    static func whisperCacheDirectory() -> URL {
        SuperscribePaths.whisperModelCacheDirectory()
    }
}
