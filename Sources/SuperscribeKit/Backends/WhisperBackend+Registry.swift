import Foundation

extension WhisperBackend: ModelRegistry {
    public static let defaultModelId = "large-v3_turbo"

    /// Hugging Face repo that hosts WhisperKit's CoreML model variants.
    public static let coreMLRepoId = "argmaxinc/whisperkit-coreml"

    public static func remoteModels() async throws -> [RemoteModelInfo] {
        let info = try await HuggingFaceHub.repoInfo(repoId: coreMLRepoId)
        return groupSiblings(info.siblings, lastModified: info.lastModified)
    }

    /// On-disk location for an installed Whisper model.
    /// Matches WhisperKit's own convention so previously-downloaded models
    /// continue to work without migration.
    public static func installPath(for modelId: String) -> URL {
        whisperKitCacheDirectory()
            .appendingPathComponent("openai_whisper-\(modelId)", isDirectory: true)
    }

    public static func installedModels() throws -> [InstalledModelInfo] {
        let dir = whisperKitCacheDirectory()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return entries.compactMap { entry -> InstalledModelInfo? in
            guard entry.hasPrefix("openai_whisper-") else { return nil }
            let id = String(entry.dropFirst("openai_whisper-".count))
            let path = dir.appendingPathComponent(entry, isDirectory: true)
            // Only count it as installed if a compiled CoreML bundle is present.
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: path.path)) ?? []
            guard contents.contains(where: { $0.hasSuffix(".mlmodelc") }) else { return nil }
            let size = directorySize(at: path)
            return InstalledModelInfo(id: id, path: path, sizeBytes: size)
        }
        .sorted { $0.id < $1.id }
    }

    // MARK: - Pure helpers (testable)

    /// Group HF repo siblings by top-level `openai_whisper-<id>/` folder and
    /// sum the total bytes per group. Files that don't live under such a
    /// folder are ignored.
    public static func groupSiblings(
        _ siblings: [HuggingFaceHub.HFSibling],
        lastModified: Date? = nil
    ) -> [RemoteModelInfo] {
        struct Bucket {
            var sizeSum: Int64 = 0
            var fileCount: Int = 0
        }
        var buckets: [String: Bucket] = [:]

        for sibling in siblings {
            let parts = sibling.rfilename.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let folder = String(parts[0])
            guard folder.hasPrefix("openai_whisper-") else { continue }
            let id = String(folder.dropFirst("openai_whisper-".count))
            var bucket = buckets[id] ?? Bucket()
            bucket.sizeSum += sibling.size ?? 0
            bucket.fileCount += 1
            buckets[id] = bucket
        }

        let repoURL = URL(string: "https://huggingface.co/\(coreMLRepoId)")!
        return buckets.keys.sorted().map { id in
            let b = buckets[id]!
            return RemoteModelInfo(
                id: id,
                repoId: coreMLRepoId,
                subpath: "openai_whisper-\(id)",
                totalSizeBytes: b.sizeSum > 0 ? b.sizeSum : nil,
                fileCount: b.fileCount,
                lastModified: lastModified,
                repoURL: repoURL
            )
        }
    }
}

// MARK: - Disk size helper

private func directorySize(at url: URL) -> Int64? {
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
