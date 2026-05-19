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
        session: URLSession = .shared,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let finalDir = try installPath(for: model.id, backend: backend)

        return try await InstallLocks.shared.withLock(for: finalDir) {
            // 1. Idempotent fast path.
            if backend == .whisperCpp {
                let binReady = isInstalled(at: finalDir, backend: backend) == true
                let encoderReady = WhisperBackend.isEncoderInstalled(modelId: model.id) == true
                if binReady == true && encoderReady == true {
                    return finalDir
                }
                if binReady == true && encoderReady == false {
                    try await WhisperEncoderInstaller.installIfNeeded(
                        model: model,
                        session: session,
                        onProgress: onProgress
                    )
                    return finalDir
                }
            }
            else if isInstalled(at: finalDir, backend: backend) == true {
                return finalDir
            }

            // 2. Disk-space pre-flight.
            let requiredBytes: Int64? =
                if backend == .whisperCpp {
                    try await WhisperEncoderInstaller.totalInstallBytes(model: model, session: session)
                }
                else {
                    model.totalSizeBytes
                }
            try preflightDiskSpace(
                requiredBytes: requiredBytes,
                installPath: finalDir
            )

            // 3. Stage.
            // Whisper models are single .bin files; everything else is a folder.
            let isSingleFile = backend == .whisperCpp
            let parent = finalDir.deletingLastPathComponent()
            let stagingPath = SuperscribeFS.stagingURL(beside: finalDir)

            do {
                try FileManager.default.createDirectory(
                    at: parent, withIntermediateDirectories: true
                )
                if isSingleFile == true {
                    // Download the single file directly into the staging path.
                    try await ModelDownloader.downloadFile(
                        model: model,
                        into: stagingPath,
                        session: session,
                        onProgress: onProgress
                    )
                }
                else {
                    try await ModelDownloader.download(
                        model: model,
                        backend: backend,
                        into: stagingPath,
                        session: session,
                        onProgress: onProgress
                    )
                }

                // 4. Atomic rename.
                if SuperscribeFS.isExistingFile(at: finalDir) == true
                    || SuperscribeFS.isExistingDirectory(at: finalDir) == true
                {
                    try SuperscribeFS.atomicReplace(
                        staging: stagingPath,
                        final: finalDir,
                        policy: .discardStagingIfFinalExists
                    )
                    return finalDir
                }
                do {
                    if SuperscribeKitTestHooks.forceModelInstallerAtomicReplaceFailure == true {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try SuperscribeFS.atomicReplace(
                        staging: stagingPath,
                        final: finalDir,
                        policy: .removeFinalThenMove
                    )
                }
                catch {
                    throw ModelInstallationError.installFailed(path: finalDir, underlying: error)
                }
                if backend == .whisperCpp {
                    try await WhisperEncoderInstaller.installIfNeeded(
                        model: model,
                        session: session,
                        onProgress: onProgress
                    )
                }
                return finalDir
            }
            catch {
                // 5. Cleanup staging on any failure.
                try? FileManager.default.removeItem(at: stagingPath)
                throw error
            }
        }
    }

    /// Per-backend convention for where a model lives on disk.
    public static func installPath(for modelId: String, backend: Backend) throws -> URL {
        try backend.installPath(for: modelId)
    }

    /// Removes an installed model from disk.
    ///
    /// Whisper: deletes the `.bin` and the Core ML `{base}-encoder.mlmodelc` bundle when present.
    /// Parakeet: deletes the model directory tree.
    public static func removeInstalled(modelId: String, backend: Backend) throws {
        switch backend {
            case .whisperCpp:
                let bin = WhisperBackend.installPath(for: modelId)
                let encoder = WhisperBackend.encoderInstallPath(for: modelId)
                let fm = FileManager.default
                if SuperscribeFS.isExistingFile(at: bin) == true {
                    try fm.removeItem(at: bin)
                }
                if SuperscribeFS.isExistingDirectory(at: encoder) == true {
                    try fm.removeItem(at: encoder)
                }
            case .parakeet:
                let path = try installPath(for: modelId, backend: backend)
                if FileManager.default.fileExists(atPath: path.path) == true {
                    try FileManager.default.removeItem(at: path)
                }
            case .appleSpeech:
                break
        }
    }

    /// Paths that `removeInstalled` would delete (for confirmation prompts).
    public static func removalPaths(modelId: String, backend: Backend) throws -> [URL] {
        switch backend {
            case .whisperCpp:
                var paths: [URL] = []
                let bin = WhisperBackend.installPath(for: modelId)
                if FileManager.default.fileExists(atPath: bin.path) == true {
                    paths.append(bin)
                }
                let encoder = WhisperBackend.encoderInstallPath(for: modelId)
                if WhisperBackend.isEncoderInstalled(modelId: modelId) == true {
                    paths.append(encoder)
                }
                return paths
            case .parakeet:
                let path = try installPath(for: modelId, backend: backend)
                if FileManager.default.fileExists(atPath: path.path) == true {
                    return [path]
                }
                return []
            case .appleSpeech:
                return []
        }
    }

    /// Returns `true` if a model looks completely installed (per-backend heuristic).
    public static func isInstalled(at path: URL, backend: Backend) -> Bool {
        switch backend {
            case .whisperCpp:
                return SuperscribeFS.isExistingFile(at: path)
            case .parakeet:
                return SuperscribeFS.containsCompiledCoreMLBundle(at: path)
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
        if FileManager.default.fileExists(atPath: probe.path) == false {
            probe = probe.deletingLastPathComponent()
        }
        // Walk up until we find an existing ancestor.
        while FileManager.default.fileExists(atPath: probe.path) == false,
            probe.pathComponents.count > 1
        {
            probe = probe.deletingLastPathComponent()
        }

        let values: URLResourceValues?
        if SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeLookupFailure == true {
            values = nil
        }
        else {
            values = try? probe.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ])
        }
        guard
            let free = values?.volumeAvailableCapacityForImportantUsage
        else {
            if SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeUnknown == true {
                return
            }
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
        if fired == true { return }
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

extension ModelInstaller {
    /// Exercises `LockSignal.wait()` after `fire()` for coverage.
    internal static func exerciseInstallLockEarlyReturnForTesting() async {
        let signal = LockSignal()
        await signal.fire()
        await signal.wait()
    }
}
