import Foundation

/// Coordinates atomic, idempotent model installation:
///
///   1. If the final dir already looks installed → no-op.
///   2. Pre-flight quota-aware free-space check.
///   3. Stage download in a sibling `<finalDir>.staging-<uuid>` directory.
///   4. Atomic `moveItem(staging → finalDir)` once every byte is on disk.
///   5. On any failure: delete the staging dir; the previous on-disk state
///      is untouched.
///
/// Concurrent installs of the *same* model serialize via a per-finalDir lock
/// so two parallel `transcribe` calls can't race.
public enum ModelInstaller {

    /// Installs `model` for `backend` if not already present. Returns the
    /// final installed directory.
    @discardableResult
    public static func install(
        model: RemoteModelInfo,
        backend: Backend,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let finalDir = try installPath(for: model.id, backend: backend)

        return try await InstallLocks.shared.withLock(for: finalDir) {
            // 1. Idempotent fast path.
            if isInstalled(at: finalDir, backend: backend) {
                return finalDir
            }

            // 2. Disk-space pre-flight.
            try preflightDiskSpace(
                requiredBytes: model.totalSizeBytes,
                installPath: finalDir
            )

            // 3. Stage.
            let stagingDir = finalDir.deletingLastPathComponent()
                .appendingPathComponent("\(finalDir.lastPathComponent).staging-\(UUID().uuidString)")

            do {
                try FileManager.default.createDirectory(
                    at: finalDir.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try await ModelDownloader.download(
                    model: model,
                    backend: backend,
                    into: stagingDir,
                    onProgress: onProgress
                )

                // 4. Atomic rename. If something somehow got into finalDir
                //    between the idempotent check and now, bail.
                if FileManager.default.fileExists(atPath: finalDir.path) {
                    // Another installer beat us; throw away staging.
                    try? FileManager.default.removeItem(at: stagingDir)
                    return finalDir
                }
                do {
                    try FileManager.default.moveItem(at: stagingDir, to: finalDir)
                }
                catch {
                    throw ModelInstallationError.installFailed(path: finalDir, underlying: error)
                }
                return finalDir
            }
            catch {
                // 5. Cleanup staging on any failure.
                try? FileManager.default.removeItem(at: stagingDir)
                throw error
            }
        }
    }

    /// Per-backend convention for where a model lives on disk.
    public static func installPath(for modelId: String, backend: Backend) throws -> URL {
        switch backend {
            case .whisper:
                return WhisperBackend.installPath(for: modelId)
            case .parakeet:
                return ParakeetBackend.installPath(for: modelId)
            case .appleSpeech:
                throw ModelInstallationError.modelNotInstalled(model: modelId, backend: backend)
        }
    }

    /// Returns `true` if a model directory looks complete (per-backend heuristic).
    public static func isInstalled(at path: URL, backend: Backend) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return false
        }
        switch backend {
            case .whisper:
                let contents =
                    (try? FileManager.default.contentsOfDirectory(atPath: path.path)) ?? []
                return contents.contains(where: { $0.hasSuffix(".mlmodelc") })
            case .parakeet:
                let contents =
                    (try? FileManager.default.contentsOfDirectory(atPath: path.path)) ?? []
                return contents.contains(where: { $0.hasSuffix(".mlmodelc") })
            case .appleSpeech:
                return false
        }
    }

    // MARK: - Disk-space pre-flight

    /// Compares the model's expected size against quota-aware free space on
    /// the install volume.
    ///
    /// - Throws: `ModelInstallationError.insufficientDiskSpace` if quota-free
    ///           is below `requiredBytes`. Warns to stderr (and continues)
    ///           if quota-free is below `requiredBytes * 1.10`.
    static func preflightDiskSpace(
        requiredBytes: Int64?,
        installPath: URL
    ) throws {
        guard let required = requiredBytes, required > 0 else { return }

        // Use the parent directory if installPath doesn't exist yet.
        var probe = installPath
        if !FileManager.default.fileExists(atPath: probe.path) {
            probe = probe.deletingLastPathComponent()
        }
        // Walk up until we find an existing ancestor.
        while !FileManager.default.fileExists(atPath: probe.path),
            probe.pathComponents.count > 1
        {
            probe = probe.deletingLastPathComponent()
        }

        guard
            let values = try? probe.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ]),
            let free = values.volumeAvailableCapacityForImportantUsage
        else {
            return  // Can't determine — let the OS error on ENOSPC.
        }

        if free < required {
            throw ModelInstallationError.insufficientDiskSpace(
                requiredBytes: required,
                availableBytes: free,
                path: probe
            )
        }
        if free < Int64(Double(required) * 1.10) {
            FileHandle.standardError.write(
                Data(
                    "Warning: free disk space is tight (need \(required) bytes, have \(free) bytes).\n"
                        .utf8
                )
            )
        }
    }
}

// MARK: - Per-finalDir lock

/// Serialises concurrent `install` calls so two callers never race on the
/// same destination directory. A single global queue is sufficient given how
/// rare model installs are (first-use only).
private actor InstallLocks {
    static let shared = InstallLocks()

    private var tail: Task<Void, Never> = Task { /* initial no-op */  }

    func withLock<T: Sendable>(
        for url: URL,
        body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        _ = url  // reserved for future per-URL locking
        let predecessor = tail
        // Use a dedicated signal task as the new tail; predecessors await it.
        let signal = LockSignal()
        let signalTask = Task<Void, Never> { await signal.wait() }
        tail = signalTask
        await predecessor.value
        defer { Task { await signal.fire() } }
        return try await body()
    }
}

private actor LockSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if fired { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    func fire() {
        fired = true
        let pending = waiters
        waiters.removeAll()
        for cont in pending { cont.resume() }
    }
}
