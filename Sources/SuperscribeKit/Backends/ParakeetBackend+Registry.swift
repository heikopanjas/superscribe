import Foundation

extension ParakeetBackend: ModelRegistry {
    public static let defaultModelId = "v3"

    /// Hugging Face org that hosts FluidAudio's CoreML model repos.
    public static let huggingFaceAuthor = "FluidInference"

    /// Single source of truth for known Parakeet ASR models.
    /// Each descriptor links the user-facing short id to:
    ///   - the bare Hugging Face repo name (for catalog + downloads), and
    ///   - the on-disk folder name FluidAudio expects (for install + load).
    public struct ModelDescriptor: Sendable, Hashable {
        public let id: String
        public let hfRepoBareName: String
        public let installFolderName: String
    }

    public static let knownDescriptors: [ModelDescriptor] = [
        .init(id: "v2", hfRepoBareName: "parakeet-tdt-0.6b-v2-coreml", installFolderName: "parakeet-tdt-0.6b-v2"),
        .init(id: "v3", hfRepoBareName: "parakeet-tdt-0.6b-v3-coreml", installFolderName: "parakeet-tdt-0.6b-v3"),
        .init(id: "tdt-ctc-110m", hfRepoBareName: "parakeet-tdt-ctc-110m-coreml", installFolderName: "parakeet-tdt-ctc-110m"),
        .init(id: "tdt-ja", hfRepoBareName: "parakeet-0.6b-ja-coreml", installFolderName: "parakeet-ja")
    ]

    /// HF repo bare name → short id (for catalog mapping).
    public static let knownRepoAliases: [String: String] = Dictionary(
        uniqueKeysWithValues: knownDescriptors.map { ($0.hfRepoBareName, $0.id) }
    )

    /// On-disk folder name → short id (for installed-model scan).
    public static let knownFolderAliases: [String: String] = Dictionary(
        uniqueKeysWithValues: knownDescriptors.map { ($0.installFolderName, $0.id) }
    )

    public static func remoteModels() async throws -> [RemoteModelInfo] {
        let repos = try await HuggingFaceHub.listAuthorRepos(
            author: huggingFaceAuthor,
            search: "parakeet"
        )
        // Parallel size lookups per repo.
        var sizes: [String: (totalBytes: Int64?, fileCount: Int?)] = [:]
        try await withThrowingTaskGroup(of: (String, Int64?, Int?).self) { group in
            for repo in repos {
                group.addTask {
                    let info = try await HuggingFaceHub.repoInfo(repoId: repo.id)
                    let total = info.siblings.reduce(0 as Int64) { $0 + ($1.size ?? 0) }
                    return (repo.id, total > 0 ? total : nil, info.siblings.count)
                }
            }
            for try await (repoId, total, count) in group {
                sizes[repoId] = (total, count)
            }
        }
        return mapRepos(repos, sizes: sizes)
    }

    /// On-disk location for an installed Parakeet model.
    /// Matches FluidAudio's `defaultCacheDirectory` so previously-downloaded
    /// models continue to work without migration.
    public static func installPath(for modelId: String) -> URL {
        let folder = installFolderName(for: modelId)
        return fluidAudioCacheDirectory().appendingPathComponent(folder, isDirectory: true)
    }

    /// Short id → on-disk folder name. Unknown ids pass through unchanged.
    public static func installFolderName(for modelId: String) -> String {
        knownDescriptors.first { $0.id == modelId }?.installFolderName ?? modelId
    }

    /// Short id → full HF repo id. Unknown ids assume `<author>/<id>`.
    public static func huggingFaceRepoId(for modelId: String) -> String {
        if let descriptor = knownDescriptors.first(where: { $0.id == modelId }) {
            return "\(huggingFaceAuthor)/\(descriptor.hfRepoBareName)"
        }
        return "\(huggingFaceAuthor)/\(modelId)"
    }

    /// Compatibility shim used by the installer's reverse lookup.
    public static func repoFolderName(for modelId: String) -> String {
        installFolderName(for: modelId)
    }

    public static func installedModels() throws -> [InstalledModelInfo] {
        let dir = fluidAudioCacheDirectory()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) == true,
            isDir.boolValue == true
        else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return entries.compactMap { entry -> InstalledModelInfo? in
            let path = dir.appendingPathComponent(entry, isDirectory: true)
            var subIsDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &subIsDir) == true,
                subIsDir.boolValue == true
            else {
                return nil
            }
            // Only count it as installed if a compiled CoreML bundle is present.
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: path.path)) ?? []
            guard contents.contains(where: { $0.hasSuffix(".mlmodelc") }) == true else { return nil }
            let id = knownFolderAliases[entry] ?? entry
            let size = parakeetDirectorySize(at: path)
            return InstalledModelInfo(id: id, path: path, sizeBytes: size)
        }
        .sorted { $0.id < $1.id }
    }

    /// FluidAudio's on-disk cache root for ASR models, matching
    /// `MLModelConfigurationUtils.defaultModelsDirectory()`:
    /// `~/Library/Application Support/FluidAudio/Models/`.
    public static func fluidAudioCacheDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return
            base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: - Pure helpers (testable)

    /// Map a list of HF repos (and their pre-fetched size info) to
    /// `RemoteModelInfo`. Unknown repos pass through with their full repo
    /// name as id.
    public static func mapRepos(
        _ repos: [HuggingFaceHub.HFRepo],
        sizes: [String: (totalBytes: Int64?, fileCount: Int?)] = [:]
    ) -> [RemoteModelInfo] {
        repos.map { repo in
            let bareName = repo.id.split(separator: "/").last.map(String.init) ?? repo.id
            let shortId = knownRepoAliases[bareName] ?? bareName
            let sizeInfo = sizes[repo.id] ?? (nil, nil)
            return RemoteModelInfo(
                id: shortId,
                repoId: repo.id,
                subpath: nil,
                totalSizeBytes: sizeInfo.totalBytes,
                fileCount: sizeInfo.fileCount,
                lastModified: repo.lastModified,
                repoURL: URL(string: "https://huggingface.co/\(repo.id)")!
            )
        }
        .sorted { $0.id < $1.id }
    }
}

// MARK: - Disk size helper

private func parakeetDirectorySize(at url: URL) -> Int64? {
    let fm = FileManager.default
    guard
        let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
    else {
        return nil
    }
    var total: Int64 = 0
    for case let item as URL in enumerator {
        let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if values?.isRegularFile == true, let size = values?.fileSize {
            total += Int64(size)
        }
    }
    return total
}
