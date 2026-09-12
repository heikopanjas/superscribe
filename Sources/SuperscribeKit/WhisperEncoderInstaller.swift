import Foundation

/// Downloads and installs whisper.cpp Core ML encoder bundles from Hugging Face.
enum WhisperEncoderInstaller {

    /// Sum of GGML `.bin` and optional encoder zip sizes for disk preflight.
    static func totalInstallBytes(
        model: RemoteModelInfo,
        session: URLSession = .shared
    ) async throws -> Int64? {
        let info = try await HuggingFaceHub.repoInfo(repoId: model.repoId, session: session)
        let binName = "ggml-\(model.id).bin"
        guard let bin = info.siblings.first(where: { $0.rfilename == binName }) else {
            return model.totalSizeBytes
        }
        var total: Int64 = 0
        if let binSize = bin.size {
            total = binSize
        }
        if let enc = WhisperBackend.encoderZipSibling(for: model.id, in: info.siblings) {
            if let encSize = enc.size {
                total += encSize
            }
        }
        if total > 0 {
            return total
        }
        return nil
    }

    /// Installs the encoder bundle when HF publishes a zip for this model.
    static func installIfNeeded(
        model: RemoteModelInfo,
        session: URLSession = .shared,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws -> Void {
        if WhisperBackend.isEncoderInstalled(modelId: model.id) == true {
            return
        }
        let info = try await HuggingFaceHub.repoInfo(repoId: model.repoId, session: session)
        guard let sibling = WhisperBackend.encoderZipSibling(for: model.id, in: info.siblings) else {
            return
        }

        let cacheDir = WhisperBackend.installPath(for: model.id).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let zipName = WhisperBackend.encoderZipRemoteName(for: model.id)
        let stagingZip = SuperscribeFS.stagingURL(beside: cacheDir.appendingPathComponent(zipName))
        let stagingExtract = SuperscribeFS.stagingURL(
            beside: cacheDir.appendingPathComponent("encoder-extract", isDirectory: true),
            label: "encoder-extract"
        )
        let finalEncoder = WhisperBackend.encoderInstallPath(for: model.id)
        defer {
            try? FileManager.default.removeItem(at: stagingZip)
            try? FileManager.default.removeItem(at: stagingExtract)
        }

        DownloadProgressReporting.emit(
            modelId: model.id,
            backend: .whisperCpp,
            currentFile: zipName,
            filesCompleted: 1,
            filesTotal: 2,
            bytesCompleted: 0,
            bytesTotal: sibling.size,
            onProgress: onProgress
        )

        try await ModelDownloader.downloadRepoFile(
            repoId: model.repoId,
            rfilename: zipName,
            into: stagingZip,
            expectedSize: sibling.size,
            session: session,
            onProgress: { bytesDone, total in
                DownloadProgressReporting.emit(
                    modelId: model.id,
                    backend: .whisperCpp,
                    currentFile: zipName,
                    filesCompleted: 1,
                    filesTotal: 2,
                    bytesCompleted: bytesDone,
                    bytesTotal: total,
                    onProgress: onProgress
                )
            }
        )

        try FileManager.default.createDirectory(at: stagingExtract, withIntermediateDirectories: true)
        try await Self.unzipArchive(at: stagingZip, into: stagingExtract)

        guard let bundle = Self.findMlmodelcBundle(under: stagingExtract) else {
            throw ModelInstallationError.installFailed(
                path: finalEncoder,
                underlying: NSError(
                    domain: "WhisperEncoderInstaller",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "No -encoder.mlmodelc bundle found inside \(zipName)."
                    ]
                )
            )
        }

        try SuperscribeFS.atomicReplace(
            staging: bundle,
            final: finalEncoder,
            policy: .replaceExisting
        )

        let bytesCompleted: Int64
        if let size = sibling.size {
            bytesCompleted = Int64(size)
        }
        else {
            bytesCompleted = 0
        }
        DownloadProgressReporting.emit(
            modelId: model.id,
            backend: .whisperCpp,
            currentFile: zipName,
            filesCompleted: 2,
            filesTotal: 2,
            bytesCompleted: bytesCompleted,
            bytesTotal: sibling.size,
            onProgress: onProgress
        )
        return
    }

    // MARK: - Private

    internal static func unzipArchive(at zip: URL, into dest: URL) async throws -> Void {
        let executable = URL(fileURLWithPath: "/usr/bin/unzip")
        let listing = try await ProcessRunner.run(executable: executable, arguments: ["-Z1", zip.path])
        guard listing.status == 0 else {
            throw ModelInstallationError.installFailed(path: dest, underlying: CocoaError(.fileReadCorruptFile))
        }
        for entry in String(decoding: listing.stdout, as: UTF8.self).split(separator: "\n") {
            let path = entry.hasSuffix("/") ? String(entry.dropLast()) : String(entry)
            _ = try ModelPathValidation.resolve(path, under: dest)
        }
        let metadata = try await ProcessRunner.run(executable: executable, arguments: ["-Z", "-l", zip.path])
        guard metadata.status == 0,
            String(decoding: metadata.stdout, as: UTF8.self).split(separator: "\n").contains(where: { $0.hasPrefix("l") }) == false
        else {
            throw ModelInstallationError.installFailed(path: dest, underlying: CocoaError(.fileReadCorruptFile))
        }
        let output = try await ProcessRunner.run(executable: executable, arguments: ["-q", "-o", zip.path, "-d", dest.path])
        guard output.status == 0 else {
            throw ModelInstallationError.installFailed(
                path: dest,
                underlying: NSError(domain: "WhisperEncoderInstaller", code: 2, userInfo: [NSLocalizedDescriptionKey: Self.decodeUnzipStderr(raw: output.stderr)])
            )
        }
    }

    private static func findMlmodelcBundle(under root: URL) -> URL? {
        let enumerator: FileManager.DirectoryEnumerator?
        if SuperscribeKitTestHooks.forceEncoderBundleEnumeratorNil == true {
            enumerator = nil
        }
        else {
            enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        }
        guard let enumerator else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix("-encoder.mlmodelc") {
            if SuperscribeFS.isExistingDirectory(at: url) == true {
                return url
            }
        }
        return nil
    }

    static func decodeUnzipStderr(raw: Data) -> String {
        let stderrData: Data
        if SuperscribeKitTestHooks.forceUnzipInvalidStderr == true {
            stderrData = Data([0xFF, 0xFE, 0xFD])
        }
        else {
            stderrData = raw
        }
        if let text = String(data: stderrData, encoding: .utf8) {
            return text
        }
        return "unzip failed"
    }
}
