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
            ? files.reduce(0) { $0 + ($1.expectedSize ?? 0) }
            : model.totalSizeBytes

        let progressActor = ProgressTracker(
            modelId: model.id,
            backend: backend,
            filesTotal: files.count,
            bytesTotal: knownTotal,
            onProgress: onProgress
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = files.makeIterator()
            var inFlight = 0

            // Prime up to maxParallelFiles tasks.
            while inFlight < maxParallelFiles, let file = iterator.next() {
                group.addTask {
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
                inFlight += 1
            }

            // As each finishes, enqueue the next.
            while let _ = try await group.next() {
                inFlight -= 1
                if let file = iterator.next() {
                    group.addTask {
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
                    inFlight += 1
                }
            }
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
        let progressActor = ProgressTracker(
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

    // MARK: - Single-file download (internal)

    private static func downloadOne(
        model: RemoteModelInfo,
        file rfilename: String,
        relPath: String,
        expectedSize: Int64?,
        stagingDir: URL,
        session: URLSession,
        progress: ProgressTracker
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

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw ModelInstallationError.httpError(status: http.statusCode, url: url)
        }

        let totalForFile: Int64? =
            (response.expectedContentLength > 0)
            ? response.expectedContentLength
            : expectedSize

        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: dest) else {
            throw ModelInstallationError.downloadFailed(
                url: url,
                underlying: NSError(
                    domain: "ModelDownloader", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot open \(dest.path) for writing."]
                )
            )
        }
        defer { try? handle.close() }

        await progress.startFile(name: relPath)

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var fileBytes: Int64 = 0
        do {
            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    fileBytes += Int64(buffer.count)
                    await progress.add(bytes: Int64(buffer.count))
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if buffer.isEmpty == false {
                try handle.write(contentsOf: buffer)
                fileBytes += Int64(buffer.count)
                await progress.add(bytes: Int64(buffer.count))
            }
        }
        catch {
            throw ModelInstallationError.downloadFailed(url: url, underlying: error)
        }

        // Rough sanity: if HF told us a size and we're way off, something's wrong.
        if let total = totalForFile, total > 0, fileBytes < total {
            throw ModelInstallationError.downloadFailed(
                url: url,
                underlying: NSError(
                    domain: "ModelDownloader", code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Truncated download: got \(fileBytes) of \(total) bytes."
                    ]
                )
            )
        }

        await progress.completeFile()
    }
}

// MARK: - Progress throttling

private actor ProgressTracker {
    private let modelId: String
    private let backend: Backend
    private let filesTotal: Int
    private let bytesTotal: Int64?
    private let onProgress: @Sendable (DownloadProgress) -> Void

    private var bytesCompleted: Int64 = 0
    private var filesCompleted: Int = 0
    private var currentFile: String = ""
    private var lastEmitAt: Date = .distantPast
    private var emitWindowStart: Date = .distantPast
    private var emitWindowStartBytes: Int64 = 0

    init(
        modelId: String,
        backend: Backend,
        filesTotal: Int,
        bytesTotal: Int64?,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) {
        self.modelId = modelId
        self.backend = backend
        self.filesTotal = filesTotal
        self.bytesTotal = bytesTotal
        self.onProgress = onProgress
        self.emitWindowStart = Date()
    }

    func startFile(name: String) {
        currentFile = name
        emit(force: true)
    }

    func add(bytes: Int64) {
        bytesCompleted += bytes
        emit(force: false)
    }

    func completeFile() {
        filesCompleted += 1
        emit(force: true)
    }

    func flush() {
        emit(force: true)
    }

    private func emit(force: Bool) {
        let now = Date()
        // Throttle to ~10 Hz unless forced.
        if force == false && now.timeIntervalSince(lastEmitAt) < 0.1 { return }
        let elapsed = now.timeIntervalSince(emitWindowStart)
        let throughput: Double?
        if elapsed >= 0.5 {
            throughput = Double(bytesCompleted - emitWindowStartBytes) / elapsed
            emitWindowStart = now
            emitWindowStartBytes = bytesCompleted
        }
        else {
            throughput = nil
        }
        lastEmitAt = now
        onProgress(
            DownloadProgress(
                modelId: modelId,
                backend: backend,
                currentFile: currentFile,
                filesCompleted: filesCompleted,
                filesTotal: filesTotal,
                bytesCompleted: bytesCompleted,
                bytesTotal: bytesTotal,
                bytesPerSecond: throughput
            )
        )
    }
}
