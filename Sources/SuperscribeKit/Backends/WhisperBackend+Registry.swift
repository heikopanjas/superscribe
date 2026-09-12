import Foundation

extension WhisperBackend: ModelRegistry {
    public static let defaultModelId = "large-v3-turbo"

    /// Hugging Face repo that hosts the GGML model `.bin` files.
    public static let huggingFaceRepoId = "ggerganov/whisper.cpp"

    public static func remoteModels() async throws -> [RemoteModelInfo] {
        return try await Self.remoteModels(session: Self.overrideRemoteModelsSession ?? Self.defaultRemoteModelsSession)
    }

    /// Override for unit tests; nil uses `defaultRemoteModelsSession`.
    internal static var overrideRemoteModelsSession: URLSession? {
        get { return Self.testState[\.overrideRemoteModelsSession] }
        set { Self.testState[\.overrideRemoteModelsSession] = newValue }
    }
    /// Default session when `overrideRemoteModelsSession` is nil (`.shared` in production).
    internal static var defaultRemoteModelsSession: URLSession {
        get { return Self.testState[\.defaultRemoteModelsSession] }
        set { Self.testState[\.defaultRemoteModelsSession] = newValue }
    }

    static func remoteModels(session: URLSession) async throws -> [RemoteModelInfo] {
        let info = try await HuggingFaceHub.repoInfo(repoId: Self.huggingFaceRepoId, session: session)
        return try Self.filterGGMLSiblings(info.siblings, lastModified: info.lastModified)
    }

    /// On-disk location for an installed Whisper GGML model.
    /// Single `.bin` file under our own cache root.
    public static func installPath(for modelId: String) -> URL {
        return Self.whisperCacheDirectory().appendingPathComponent("\(modelId).bin")
    }

    public static func installedModels() throws -> [InstalledModelInfo] {
        let dir = Self.whisperCacheDirectory()
        guard FileManager.default.fileExists(atPath: dir.path) == true else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return
            entries
            .filter { $0.hasSuffix(".bin") && SuperscribeFS.isExistingFile(at: dir.appendingPathComponent($0)) }
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
        return Self.whisperCacheDirectory().appendingPathComponent(
            "\(Self.encoderBaseId(for: modelId))-encoder.mlmodelc",
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
        return "ggml-\(Self.encoderBaseId(for: modelId))-encoder.mlmodelc.zip"
    }

    /// Finds the encoder zip sibling for `modelId`, if published on the repo.
    public static func encoderZipSibling(
        for modelId: String,
        in siblings: [HuggingFaceHub.HFSibling]
    ) -> HuggingFaceHub.HFSibling? {
        let name = Self.encoderZipRemoteName(for: modelId)
        return siblings.first { $0.rfilename == name }
    }

    /// `true` when the Core ML encoder bundle directory exists.
    public static func isEncoderInstalled(modelId: String) -> Bool {
        return SuperscribeFS.isExistingDirectory(at: Self.encoderInstallPath(for: modelId))
    }

    // MARK: - Pure helpers (testable)

    /// Filter HF repo siblings to those matching `ggml-<id>.bin` at the root
    /// of the repo (no subdirectory). The capture group becomes the model id.
    public static func filterGGMLSiblings(
        _ siblings: [HuggingFaceHub.HFSibling],
        lastModified: Date? = nil
    ) throws -> [RemoteModelInfo] {
        let repoURL = try HTTPURL.make(host: "huggingface.co", path: "/\(Self.huggingFaceRepoId)")
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
                repoId: Self.huggingFaceRepoId,
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
        return SuperscribePaths.whisperModelCacheDirectory()
    }
}
