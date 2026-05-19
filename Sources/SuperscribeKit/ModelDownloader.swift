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
        guard let total = bytesTotal, total > 0 else { return nil }
        return min(1, Double(bytesCompleted) / Double(total))
    }
}

/// URLSession-based downloader for a single model from Hugging Face Hub.
///
/// - Atomic from the caller's perspective: writes go into `stagingDir`,
///   never the final destination. The caller (`ModelInstaller`) is
///   responsible for the final atomic rename.
/// - Live progress: invokes `onProgress` from a background queue, throttled
///   to ~10 Hz.
/// - At most `maxParallelFiles` concurrent file downloads.
public enum ModelDownloader {

    public static let maxParallelFiles = 4

    /// Downloads every file for `model` (filtered by `model.subpath` if set)
    /// from Hugging Face into `stagingDir`. Files are placed at their
    /// repo-relative path with the `subpath/` prefix stripped (if any).
    ///
    /// - Throws: `ModelInstallationError.downloadFailed`,
    ///           `ModelInstallationError.httpError`.
    public static func download(
        model: RemoteModelInfo,
        backend: Backend,
        into stagingDir: URL,
        session: URLSession = .shared,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        // Re-fetch the latest sibling list so we never miss files added since
        // the catalog was cached.
        let info = try await HuggingFaceHub.repoInfo(repoId: model.repoId, session: session)

        // Filter + compute relative install paths.
        let files: [(rfilename: String, relPath: String, expectedSize: Int64?)] = info.siblings
            .compactMap { sibling in
                if let subpath = model.subpath {
                    let prefix = subpath.hasSuffix("/") ? subpath : subpath + "/"
                    guard sibling.rfilename.hasPrefix(prefix) == true else { return nil }
                    let rel = String(sibling.rfilename.dropFirst(prefix.count))
                    guard rel.isEmpty == false else { return nil }
                    return (sibling.rfilename, rel, sibling.size)
                }
                else {
                    return (sibling.rfilename, sibling.rfilename, sibling.size)
                }
            }

        guard files.isEmpty == false else {
            throw ModelInstallationError.downloadFailed(
                url: model.repoURL,
                underlying: NSError(
                    domain: "ModelDownloader", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No files matched model subpath."]
                )
            )
        }

        try FileManager.default.createDirectory(
            at: stagingDir, withIntermediateDirectories: true
        )

        // Total may be nil if any file size is unknown; in that case overall
        // percentage will be nil too.
        let knownTotal: Int64? =
            files.allSatisfy { $0.expectedSize != nil }
            ? files.reduce(Int64(0)) { $0 + $1.expectedSize! }
            : model.totalSizeBytes

        let progressActor = DownloadProgressTracker(
            modelId: model.id,
            backend: backend,
            filesTotal: files.count,
            bytesTotal: knownTotal,
            onProgress: onProgress
        )

        try await ConcurrencyHelpers.withBoundedVoidThrowingTaskGroup(
            limit: maxParallelFiles,
            items: files
        ) { file in
            try await downloadOne(
                model: model,
                file: file.rfilename,
                relPath: file.relPath,
                expectedSize: file.expectedSize,
                stagingDir: stagingDir,
                session: session,
                progress: progressActor
            )
        }

        await progressActor.flush()
    }

    // MARK: - Single-file entry point (for whisper .bin models)

    /// Downloads a single-file model (e.g. a GGML `.bin`) directly to `dest`.
    /// The file at `dest` is the staging path; the caller is responsible for
    /// the atomic rename to the final location.
    public static func downloadFile(
        model: RemoteModelInfo,
        into dest: URL,
        session: URLSession = .shared,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        // For single-file models subpath is nil and rfilename == model filename.
        guard
            let sibling = try await {
                let info = try await HuggingFaceHub.repoInfo(repoId: model.repoId, session: session)
                let filename = "ggml-\(model.id).bin"
                return info.siblings.first { $0.rfilename == filename }
            }()
        else {
            throw ModelInstallationError.downloadFailed(
                url: model.repoURL,
                underlying: NSError(
                    domain: "ModelDownloader", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "ggml-\(model.id).bin not found in repo."]
                )
            )
        }
        let progressActor = DownloadProgressTracker(
            modelId: model.id,
            backend: .whisperCpp,
            filesTotal: 1,
            bytesTotal: sibling.size,
            onProgress: onProgress
        )
        let rfilename = "ggml-\(model.id).bin"
        try await downloadOne(
            model: model,
            file: rfilename,
            relPath: dest.lastPathComponent,
            expectedSize: sibling.size,
            stagingDir: dest.deletingLastPathComponent(),
            session: session,
            progress: progressActor
        )
        await progressActor.flush()
    }

    /// Downloads one repo-root file to `dest` (used for whisper encoder zips).
    public static func downloadRepoFile(
        repoId: String,
        rfilename: String,
        into dest: URL,
        expectedSize: Int64?,
        session: URLSession = .shared,
        onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async throws {
        let url = URL(string: "https://huggingface.co/\(repoId)/resolve/main/\(rfilename)")!
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue(HuggingFaceHub.userAgent, forHTTPHeaderField: "User-Agent")

        let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (asyncBytes, response) = try await session.bytes(for: request)
        }
        catch {
            throw ModelInstallationError.downloadFailed(url: url, underlying: error)
        }

        if let http = response as? HTTPURLResponse, http.isSuccess == false {
            throw ModelInstallationError.httpError(status: http.statusCode, url: url)
        }

        let totalForFile: Int64? =
            (response.expectedContentLength > 0)
            ? response.expectedContentLength
            : expectedSize

        let tracker = CumulativeByteTracker()
        _ = try await streamBytes(
            from: asyncBytes,
            to: dest,
            sourceURL: url,
            expectedSize: totalForFile
        ) { chunk in
            let total = await tracker.add(chunk)
            onProgress?(total, totalForFile)
        }
    }

    /// Writes an async byte stream to `dest`, invoking `onChunk` with incremental
    /// byte counts after each buffer flush.
    static func streamBytes<S: AsyncSequence>(
        from bytes: S,
        to dest: URL,
        sourceURL: URL,
        expectedSize: Int64?,
        onChunk: (@Sendable (Int64) async -> Void)? = nil
    ) async throws -> Int64 where S.Element == UInt8 {
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        }
        catch {
            throw ModelInstallationError.downloadFailed(url: sourceURL, underlying: error)
        }

        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle: FileHandle? =
            if SuperscribeKitTestHooks.forceModelDownloaderFileHandleFailure == true {
                nil
            }
            else {
                try? FileHandle(forWritingTo: dest)
            }
        guard let handle else {
            throw ModelInstallationError.downloadFailed(
                url: sourceURL,
                underlying: NSError(
                    domain: "ModelDownloader", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot open \(dest.path) for writing."]
                )
            )
        }
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var fileBytes: Int64 = 0
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    let chunkSize = Int64(buffer.count)
                    fileBytes += chunkSize
                    if let onChunk {
                        await onChunk(chunkSize)
                    }
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if buffer.isEmpty == false {
                try handle.write(contentsOf: buffer)
                let chunkSize = Int64(buffer.count)
                fileBytes += chunkSize
                if let onChunk {
                    await onChunk(chunkSize)
                }
            }
        }
        catch {
            throw ModelInstallationError.downloadFailed(url: sourceURL, underlying: error)
        }

        if let total = expectedSize, total > 0, fileBytes < total {
            throw ModelInstallationError.downloadFailed(
                url: sourceURL,
                underlying: NSError(
                    domain: "ModelDownloader", code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Truncated download: got \(fileBytes) of \(total) bytes."
                    ]
                )
            )
        }

        return fileBytes
    }

    // MARK: - Single-file download (internal)

    private static func downloadOne(
        model: RemoteModelInfo,
        file rfilename: String,
        relPath: String,
        expectedSize: Int64?,
        stagingDir: URL,
        session: URLSession,
        progress: DownloadProgressTracker
    ) async throws {
        let url = URL(string: "https://huggingface.co/\(model.repoId)/resolve/main/\(rfilename)")!
        let dest = stagingDir.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(HuggingFaceHub.userAgent, forHTTPHeaderField: "User-Agent")

        let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (asyncBytes, response) = try await session.bytes(for: request)
        }
        catch {
            throw ModelInstallationError.downloadFailed(url: url, underlying: error)
        }

        if let http = response as? HTTPURLResponse, http.isSuccess == false {
            throw ModelInstallationError.httpError(status: http.statusCode, url: url)
        }

        let totalForFile: Int64? =
            (response.expectedContentLength > 0)
            ? response.expectedContentLength
            : expectedSize

        await progress.startFile(name: rfilename)

        _ = try await streamBytes(
            from: asyncBytes,
            to: dest,
            sourceURL: url,
            expectedSize: totalForFile
        ) { chunk in
            await progress.add(bytes: chunk)
        }

        await progress.completeFile()
    }
}

// MARK: - Progress throttling

private actor CumulativeByteTracker {
    private var bytes: Int64 = 0

    func add(_ chunk: Int64) -> Int64 {
        bytes += chunk
        return bytes
    }
}
