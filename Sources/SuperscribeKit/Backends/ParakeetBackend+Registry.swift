import FluidAudio
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
        public let aliases: [String]
        internal let version: AsrModelVersion
        internal let bundles: Set<String>
        internal let vocabulary: String
    }

    public static let knownDescriptors: [ModelDescriptor] = [
        .init(
            id: "v2", hfRepoBareName: "parakeet-tdt-0.6b-v2-coreml", installFolderName: "parakeet-tdt-0.6b-v2", aliases: [], version: .v2, bundles: ModelNames.ASR.requiredModels,
            vocabulary: ModelNames.ASR.vocabularyFile),
        .init(
            id: "v3", hfRepoBareName: "parakeet-tdt-0.6b-v3-coreml", installFolderName: "parakeet-tdt-0.6b-v3", aliases: [], version: .v3, bundles: ModelNames.ASR.requiredModelsV3,
            vocabulary: ModelNames.ASR.vocabularyFile),
        .init(
            id: "tdt-ctc-110m", hfRepoBareName: "parakeet-tdt-ctc-110m-coreml", installFolderName: "parakeet-tdt-ctc-110m", aliases: ["tdtctc110m", "110m"], version: .tdtCtc110m,
            bundles: ModelNames.ASR.requiredModelsFused, vocabulary: ModelNames.ASR.vocabularyFile),
        .init(
            id: "tdt-ja", hfRepoBareName: "parakeet-0.6b-ja-coreml", installFolderName: "parakeet-ja", aliases: ["tdtja", "ja"], version: .tdtJa, bundles: ModelNames.TDTJa.requiredModels,
            vocabulary: ModelNames.TDTJa.vocabularyFile)
    ]

    internal static func descriptor(for model: String) throws -> ModelDescriptor {
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let descriptor = Self.knownDescriptors.first(where: { $0.id == id || $0.aliases.contains(id) }) else {
            throw UnsupportedModelError(backend: .parakeet, model: model)
        }
        return descriptor
    }

    /// HF repo bare name → short id (for catalog mapping).
    public static let knownRepoAliases: [String: String] = Dictionary(
        uniqueKeysWithValues: ParakeetBackend.knownDescriptors.map { ($0.hfRepoBareName, $0.id) }
    )

    /// On-disk folder name → short id (for installed-model scan).
    public static let knownFolderAliases: [String: String] = Dictionary(
        uniqueKeysWithValues: ParakeetBackend.knownDescriptors.map { ($0.installFolderName, $0.id) }
    )

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
        let repos = try await HuggingFaceHub.listAuthorRepos(
            author: Self.huggingFaceAuthor,
            search: "parakeet",
            session: session
        )
        let sizes = try await Self.fetchRepoSizes(
            for: repos,
            repoInfo: { repoId in
                try await HuggingFaceHub.repoInfo(repoId: repoId, session: session)
            })
        return try Self.mapRepos(repos, sizes: sizes)
    }

    /// Fetches total bytes + file counts for HF repos with bounded concurrency.
    static func fetchRepoSizes(
        for repos: [HuggingFaceHub.HFRepo],
        maxConcurrent: Int = ModelDownloader.maxParallelFiles,
        session: URLSession = .shared,
        repoInfo: (@Sendable (String) async throws -> HuggingFaceHub.HFRepoInfo)? = nil
    ) async throws -> [String: (totalBytes: Int64?, fileCount: Int?)] {
        let resolveInfo =
            repoInfo ?? { repoId in
                try await HuggingFaceHub.repoInfo(repoId: repoId, session: session)
            }
        let pairs = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(
            limit: maxConcurrent,
            items: repos
        ) { repo in
            let info = try await resolveInfo(repo.id)
            let total = info.siblings.reduce(0 as Int64) { $0 + ($1.size ?? 0) }
            return (repo.id, total > 0 ? total : nil, info.siblings.count)
        }
        var sizes: [String: (totalBytes: Int64?, fileCount: Int?)] = [:]
        for (repoId, total, count) in pairs {
            sizes[repoId] = (total, count)
        }
        return sizes
    }

    /// On-disk location for an installed Parakeet model.
    /// Matches FluidAudio's `defaultCacheDirectory` so previously-downloaded
    /// models continue to work without migration.
    public static func installPath(for modelId: String) throws -> URL {
        let folder = try Self.installFolderName(for: modelId)
        return Self.fluidAudioCacheDirectory().appendingPathComponent(folder, isDirectory: true)
    }

    /// Short id → on-disk folder name. Unknown ids throw.
    public static func installFolderName(for modelId: String) throws -> String {
        return try Self.descriptor(for: modelId).installFolderName
    }

    /// Short id → full HF repo id. Unknown ids throw.
    public static func huggingFaceRepoId(for modelId: String) throws -> String {
        return "\(Self.huggingFaceAuthor)/\(try Self.descriptor(for: modelId).hfRepoBareName)"
    }

    public static func installedModels() throws -> [InstalledModelInfo] {
        let dir = Self.fluidAudioCacheDirectory()
        guard SuperscribeFS.isExistingDirectory(at: dir) == true else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return entries.compactMap { entry -> InstalledModelInfo? in
            guard entry.contains(".staging-") == false else { return nil }
            let path = dir.appendingPathComponent(entry, isDirectory: true)
            guard SuperscribeFS.isExistingDirectory(at: path) == true else { return nil }
            guard let descriptor = Self.knownDescriptors.first(where: { $0.installFolderName == entry }) else { return nil }
            guard ModelArtifacts.parakeet(at: path, descriptor: descriptor) == true else { return nil }
            let id = descriptor.id
            let size = parakeetDirectorySize(at: path)
            return InstalledModelInfo(id: id, path: path, sizeBytes: size)
        }
        .sortedById()
    }

    /// FluidAudio's on-disk cache root for ASR models, matching
    /// `MLModelConfigurationUtils.defaultModelsDirectory()`:
    /// `~/Library/Application Support/FluidAudio/Models/`.
    public static func fluidAudioCacheDirectory() -> URL {
        return SuperscribePaths.fluidAudioModelsDirectory()
    }

    // MARK: - Pure helpers (testable)

    /// Map a list of HF repos (and their pre-fetched size info) to
    /// `RemoteModelInfo`. Only supported descriptor entries are advertised.
    public static func mapRepos(
        _ repos: [HuggingFaceHub.HFRepo],
        sizes: [String: (totalBytes: Int64?, fileCount: Int?)] = [:]
    ) throws -> [RemoteModelInfo] {
        return try repos.compactMap { repo -> RemoteModelInfo? in
            let bareName = repo.id.split(separator: "/").last.map(String.init) ?? repo.id
            guard repo.id == "\(Self.huggingFaceAuthor)/\(bareName)", let shortId = Self.knownRepoAliases[bareName] else { return nil }
            let sizeInfo = sizes[repo.id] ?? (nil, nil)
            return RemoteModelInfo(
                id: shortId,
                repoId: repo.id,
                subpath: nil,
                totalSizeBytes: sizeInfo.totalBytes,
                fileCount: sizeInfo.fileCount,
                lastModified: repo.lastModified,
                repoURL: try HTTPURL.make(host: "huggingface.co", path: "/\(repo.id)")
            )
        }
        .sortedById()
    }
}

private func parakeetDirectorySize(at url: URL) -> Int64? {
    if SuperscribeKitTestHooks.forceParakeetDirectorySizeEnumeratorFailure == true {
        return nil
    }
    let fm = FileManager.default
    let enumerator: FileManager.DirectoryEnumerator?
    if SuperscribeKitTestHooks.forceParakeetDirectorySizeNilEnumerator == true {
        enumerator = nil
    }
    else {
        enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
    }
    guard let enumerator else {
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
