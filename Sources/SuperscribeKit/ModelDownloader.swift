import Darwin
import Foundation

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

    /// Downloads an explicit file selection from `model.repoId` into `stagingDir` with bounded parallelism.
    ///
    /// - Throws: `ModelInstallationError.downloadFailed`, `ModelInstallationError.httpError`.
    internal static func download(
        files: [ModelDownloadFile],
        model: RemoteModelInfo,
        backend: Backend?,
        into stagingDir: URL,
        session: URLSession,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> Void {
        guard files.isEmpty == false else {
            throw ModelInstallationError.downloadFailed(
                url: model.repoURL,
                underlying: NSError(
                    domain: "ModelDownloader", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No repository files matched the model."]
                )
            )
        }

        try FileManager.default.createDirectory(
            at: stagingDir, withIntermediateDirectories: true
        )

        // Fall back to the catalog total when any file size is unknown; without either, percentages are unavailable.
        let knownTotal = ModelDownloadFile.totalSize(of: files) ?? model.totalSizeBytes

        let progressActor = DownloadProgressTracker(
            modelId: model.id,
            backend: backend,
            filesTotal: files.count,
            bytesTotal: knownTotal,
            onProgress: onProgress
        )

        try await ConcurrencyHelpers.withBoundedVoidThrowingTaskGroup(
            limit: Self.maxParallelFiles,
            items: files
        ) { file in
            try await Self.downloadOne(
                repoId: model.repoId,
                file: file.rfilename,
                relPath: file.relativePath,
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
    ) async throws -> Void {
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
        try await Self.downloadOne(
            repoId: model.repoId,
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
    ) async throws -> Void {
        let tracker = CumulativeByteTracker()
        try await Self.downloadBytes(repoId: repoId, filename: rfilename, into: dest, expectedSize: expectedSize, session: session) { bytes, total in
            let done = await tracker.add(bytes)
            onProgress?(done, total)
        }
    }

    private static func downloadBytes(
        repoId: String, filename: String, into destination: URL, expectedSize: Int64?, session: URLSession, onChunk: @escaping @Sendable (Int64, Int64?) async -> Void
    ) async throws -> Void {
        try Task.checkCancellation()
        let url = try ModelPathValidation.downloadURL(repoId: repoId, filename: filename)
        let destination = try ModelPathValidation.resolve(destination.lastPathComponent, under: destination.deletingLastPathComponent())
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue(HuggingFaceHub.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            do {
                if let http = response as? HTTPURLResponse, http.isSuccess == false {
                    throw ModelInstallationError.httpError(status: http.statusCode, url: url)
                }
                let size = expectedSize ?? (response.expectedContentLength >= 0 ? response.expectedContentLength : nil)
                _ = try await Self.streamBytes(from: bytes, to: destination, sourceURL: url, expectedSize: size) { chunk in
                    await onChunk(chunk, size)
                }
            }
            catch {
                bytes.task.cancel()
                // Consume the cancelled iterator so an unconsumed response cannot retain the session. A cancelled
                // caller's iterator throws before reading, so drain from a task that does not inherit cancellation.
                await Task.detached {
                    var iterator = bytes.makeAsyncIterator()
                    _ = try? await iterator.next()
                }.value
                throw error
            }
        }
        catch {
            try Cancellation.propagate(error)
            if (error is ModelInstallationError) == true { throw error }
            throw ModelInstallationError.downloadFailed(url: url, underlying: error)
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
            try Cancellation.propagate(error)
            throw ModelInstallationError.downloadFailed(url: sourceURL, underlying: error)
        }

        try Task.checkCancellation()
        let descriptor = SuperscribeKitTestHooks.forceModelDownloaderFileHandleFailure == true ? -1 : open(dest.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw ModelInstallationError.downloadFailed(url: sourceURL, underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var completed = false
        defer {
            try? handle.close()
            if completed == false { try? FileManager.default.removeItem(at: dest) }
        }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var fileBytes: Int64 = 0
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try Task.checkCancellation()
                    try handle.write(contentsOf: buffer)
                    let chunkSize = Int64(buffer.count)
                    fileBytes += chunkSize
                    if let onChunk {
                        await onChunk(chunkSize)
                    }
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            try Task.checkCancellation()
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
            try Cancellation.propagate(error)
            throw ModelInstallationError.downloadFailed(url: sourceURL, underlying: error)
        }

        if let total = expectedSize, total >= 0, fileBytes != total {
            throw ModelInstallationError.downloadFailed(
                url: sourceURL,
                underlying: NSError(
                    domain: "ModelDownloader", code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Incorrect download size: got \(fileBytes) of \(total) bytes."
                    ]
                )
            )
        }

        completed = true
        return fileBytes
    }

    // MARK: - Single-file download (internal)

    private static func downloadOne(
        repoId: String,
        file rfilename: String,
        relPath: String,
        expectedSize: Int64?,
        stagingDir: URL,
        session: URLSession,
        progress: DownloadProgressTracker
    ) async throws -> Void {
        let dest = try ModelPathValidation.resolve(relPath, under: stagingDir)
        await progress.startFile(name: rfilename)
        try await Self.downloadBytes(repoId: repoId, filename: rfilename, into: dest, expectedSize: expectedSize, session: session) { chunk, _ in
            await progress.add(bytes: chunk)
        }
        await progress.completeFile()
    }

}
