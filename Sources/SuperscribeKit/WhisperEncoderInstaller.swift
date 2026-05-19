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
        var total = bin.size ?? 0
        if let enc = WhisperBackend.encoderZipSibling(for: model.id, in: info.siblings),
            let encSize = enc.size
        {
            total += encSize
        }
        return total > 0 ? total : nil
    }

    /// Installs the encoder bundle when HF publishes a zip for this model.
    static func installIfNeeded(
        model: RemoteModelInfo,
        session: URLSession = .shared,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
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
        try unzipArchive(at: stagingZip, into: stagingExtract)

        guard let bundle = findMlmodelcBundle(under: stagingExtract) else {
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
            policy: .removeFinalThenMove
        )

        DownloadProgressReporting.emit(
            modelId: model.id,
            backend: .whisperCpp,
            currentFile: zipName,
            filesCompleted: 2,
            filesTotal: 2,
            bytesCompleted: sibling.size ?? 0,
            bytesTotal: sibling.size,
            onProgress: onProgress
        )
        return
    }

    // MARK: - Private

    private static func unzipArchive(at zip: URL, into dest: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zip.path, "-d", dest.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let raw = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = decodeUnzipStderr(raw: raw)
            throw ModelInstallationError.installFailed(
                path: dest,
                underlying: NSError(
                    domain: "WhisperEncoderInstaller",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: err]
                )
            )
        }
        return
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
        let stderrData =
            SuperscribeKitTestHooks.forceUnzipInvalidStderr == true
            ? Data([0xFF, 0xFE, 0xFD]) : raw
        return String(data: stderrData, encoding: .utf8) ?? "unzip failed"
    }
}
