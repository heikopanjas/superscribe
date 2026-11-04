import Foundation

/// Validates existing artifacts, stages complete downloads, then atomically publishes them.
/// A cancellation-aware FIFO coordinates installation, removal, and confirmation paths.
/// Failed staging preserves the previous destination; explicit Whisper installs also repair
/// a missing published encoder. Encoders remain while installed variants share them.
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
        if backend == .appleSpeech {
            _ = try Self.installPath(for: model.id, backend: backend)
            return try await ModelLifecycleCoordinator.shared.withLock {
                return try await AppleSpeechAssetInstaller.ensureInstalled(
                    localeId: model.id,
                    backend: backend,
                    onProgress: onProgress
                )
            }
        }

        if backend == .parakeet {
            let repository = try ParakeetBackend.huggingFaceRepoId(for: model.id)
            guard model.repoId == repository else {
                throw UnsupportedModelError(backend: backend, model: model.repoId)
            }
        }
        let finalDir = try Self.installPath(for: model.id, backend: backend)

        return try await ModelLifecycleCoordinator.shared.withLock {
            // 1. Idempotent fast path.
            if backend == .whisperCpp {
                let binReady = await Self.isInstalled(at: finalDir, backend: backend, modelId: model.id, expectedSize: model.totalSizeBytes) == true
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
            else if await Self.isInstalled(at: finalDir, backend: backend, modelId: model.id, expectedSize: model.totalSizeBytes) == true {
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
            try Self.preflightDiskSpace(
                requiredBytes: requiredBytes,
                installPath: finalDir
            )

            // 3. Stage, validate, and publish.
            // Whisper models are single .bin files; everything else is a folder.
            let installed = try await Self.stageAndPublish(
                finalDir: finalDir,
                download: { stagingPath in
                    if backend == .whisperCpp {
                        try await ModelDownloader.downloadFile(model: model, into: stagingPath, session: session, onProgress: onProgress)
                    }
                    else {
                        // Re-fetch the sibling list so files added since the catalog was cached are not missed,
                        // then download only what FluidAudio loads.
                        let files = try ParakeetBackend.descriptor(for: model.id).files(in: try await HuggingFaceHub.repoInfo(repoId: model.repoId, session: session).siblings)
                        try await ModelDownloader.download(files: files, model: model, backend: backend, into: stagingPath, session: session, onProgress: onProgress)
                    }
                },
                validate: { stagingPath in
                    return await Self.isInstalled(at: stagingPath, backend: backend, modelId: model.id, expectedSize: model.totalSizeBytes)
                }
            )
            if backend == .whisperCpp {
                try await WhisperEncoderInstaller.installIfNeeded(
                    model: model,
                    session: session,
                    onProgress: onProgress
                )
            }
            return installed
        }
    }

    /// Downloads into a sibling staging path, validates it, and atomically replaces `finalDir`.
    /// Staging is removed on any failure, so an existing destination is preserved.
    internal static func stageAndPublish(
        finalDir: URL,
        download: (URL) async throws -> Void,
        validate: (URL) async -> Bool
    ) async throws -> URL {
        let stagingPath = SuperscribeFS.stagingURL(beside: finalDir)
        do {
            try FileManager.default.createDirectory(at: finalDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await download(stagingPath)
            guard await validate(stagingPath) == true else {
                throw ModelInstallationError.installFailed(path: stagingPath, underlying: CocoaError(.fileReadCorruptFile))
            }
            do {
                if SuperscribeKitTestHooks.forceModelInstallerAtomicReplaceFailure == true {
                    throw CocoaError(.fileWriteUnknown)
                }
                try SuperscribeFS.atomicReplace(staging: stagingPath, final: finalDir, policy: .replaceExisting)
            }
            catch {
                throw ModelInstallationError.installFailed(path: finalDir, underlying: error)
            }
            return finalDir
        }
        catch {
            try? FileManager.default.removeItem(at: stagingPath)
            throw error
        }
    }

    /// Per-backend convention for where a model lives on disk.
    public static func installPath(for modelId: String, backend: Backend) throws -> URL {
        try ModelPathValidation.identifier(modelId)
        let path = try backend.installPath(for: modelId)
        if path.isFileURL == true {
            let root = backend == .whisperCpp ? SuperscribePaths.whisperModelsDirectory() : SuperscribePaths.parakeetModelsDirectory()
            return try ModelPathValidation.resolve(path.lastPathComponent, under: root)
        }
        return path
    }

    /// Removes an installed model from disk.
    ///
    /// Whisper: deletes the `.bin` and the Core ML `{base}-encoder.mlmodelc` bundle when present.
    /// Parakeet: deletes the model directory tree.
    public static func removeInstalled(modelId: String, backend: Backend) async throws -> Void {
        _ = try Self.installPath(for: modelId, backend: backend)
        try await ModelLifecycleCoordinator.shared.withLock {
            try await Self.removeUnlocked(modelId: modelId, backend: backend)
        }
    }

    private static func removeUnlocked(modelId: String, backend: Backend) async throws -> Void {

        if backend == .appleSpeech {
            await AppleSpeechAssetInstaller.release(localeId: modelId)
            return
        }
        for path in try await Self.removalPathsUnlocked(modelId: modelId, backend: backend) {
            try Task.checkCancellation()
            try FileManager.default.removeItem(at: path)
        }
    }

    /// Paths that `removeInstalled` would delete (for confirmation prompts).
    public static func removalPaths(modelId: String, backend: Backend) async throws -> [URL] {
        _ = try Self.installPath(for: modelId, backend: backend)
        return try await ModelLifecycleCoordinator.shared.withLock {
            return try await Self.removalPathsUnlocked(modelId: modelId, backend: backend)
        }
    }

    private static func removalPathsUnlocked(modelId: String, backend: Backend) async throws -> [URL] {

        switch backend {
            case .appleSpeech:
                let canonicalId = (try? await AppleSpeechSupport.resolveModelId(modelId)) ?? AppleSpeechSupport.normalizeLocaleId(modelId)
                if try await AppleSpeechCatalog.installedModels().contains(where: { $0.id == canonicalId && $0.state.hasReservation }) == true {
                    return [try AppleSpeechSupport.installMarkerURL(for: canonicalId)]
                }
                return []
            case .whisperCpp:
                var paths: [URL] = []
                let bin = WhisperBackend.installPath(for: modelId)
                if SuperscribeFS.isExistingFile(at: bin) == true {
                    paths.append(bin)
                }
                let encoder = WhisperBackend.encoderInstallPath(for: modelId)
                let base = WhisperBackend.encoderBaseId(for: modelId)
                let shared = try WhisperBackend.installedModels().contains { model in
                    return model.id != modelId && WhisperBackend.encoderBaseId(for: model.id) == base
                }
                if WhisperBackend.isEncoderInstalled(modelId: modelId) == true, shared == false {
                    paths.append(encoder)
                }
                return paths
            case .parakeet:
                let path = try Self.installPath(for: modelId, backend: backend)
                if FileManager.default.fileExists(atPath: path.path) == true {
                    return [path]
                }
                return []
        }
    }

    /// Checks required artifact presence and known binary size without inference.
    public static func isInstalled(at path: URL, backend: Backend, modelId: String? = nil, expectedSize: Int64? = nil) async -> Bool {
        switch backend {
            case .whisperCpp:
                return ModelArtifacts.nonemptyFile(at: path, expectedSize: expectedSize)
            case .parakeet:
                let id = modelId ?? ParakeetBackend.knownFolderAliases[path.lastPathComponent]
                guard let id, let descriptor = try? ParakeetBackend.descriptor(for: id) else { return false }
                return ModelArtifacts.parakeet(at: path, descriptor: descriptor)
            case .appleSpeech:
                guard let localeId = AppleSpeechSupport.localeId(fromInstallMarker: path) else {
                    return false
                }
                return await AppleSpeechAssetInstaller.isInstalled(localeId: localeId)
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
    ) throws -> Void {
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
