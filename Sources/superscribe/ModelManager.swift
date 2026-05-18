import ArgumentParser
import Foundation
import SuperscribeKit

/// Catalog fetch, install state, and installation orchestration for models.
final class ModelManager {
    private init() {}

    /// Fetches the catalog for `backend`, using the on-disk `CatalogStore` when
    /// possible. When `forceRefresh` is true, or no entry exists for the
    /// backend yet, hits the network and persists the response.
    static func catalog(
        for backend: Backend,
        forceRefresh: Bool = false
    ) async throws -> (entry: CatalogEntry, refreshed: Bool) {
        if forceRefresh == false,
            let existing = (try? CatalogStore.load())?.entry(for: backend)
        {
            return (existing, false)
        }
        let models = try await remoteModels(for: backend)
        let entry = CatalogEntry(fetchedAt: Date(), models: models)
        try CatalogStore.update(entry, for: backend)
        return (entry, true)
    }

    /// Backend → its `remoteModels()` static call.
    static func remoteModels(for backend: Backend) async throws -> [RemoteModelInfo] {
        switch backend {
            case .parakeet: return try await ParakeetBackend.remoteModels()
            case .whisperCpp: return try await WhisperBackend.remoteModels()
            case .appleSpeech: return []
        }
    }

    /// Backend → its `installedModels()` static call.
    static func installedModels(for backend: Backend) throws -> [InstalledModelInfo] {
        switch backend {
            case .parakeet: return try ParakeetBackend.installedModels()
            case .whisperCpp: return try WhisperBackend.installedModels()
            case .appleSpeech: return []
        }
    }

    /// If `model` isn't installed for `backend`, look it up in the catalog
    /// (auto-fetch if missing) and install it via `ModelInstaller`.
    /// No-op when the model is already on disk.
    static func ensureModelInstalled(_ model: String, backend: Backend) async throws {
        let installed = (try? installedModels(for: backend)) ?? []
        if installed.contains(where: { $0.id == model }) == true { return }

        FileHandle.standardError.write(
            Data(
                "Model '\(model)' not installed for backend '\(backend.rawValue)'; downloading...\n".utf8
            )
        )

        let (entry, _) = try await catalog(for: backend, forceRefresh: false)
        guard let info = entry.models.first(where: { $0.id == model }) else {
            throw ModelInstallationError.unknownModel(
                model: model,
                backend: backend,
                available: entry.models.map(\.id)
            )
        }
        _ = try await ModelInstaller.install(
            model: info,
            backend: backend,
            onProgress: makeDownloadProgressHandler()
        )
        // Clear the progress line.
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
        FileHandle.standardError.write(
            Data("Installed '\(model)' for backend '\(backend.rawValue)'.\n".utf8)
        )
    }

    /// Returns a throttled stderr progress handler for `ModelInstaller`/`ModelDownloader`.
    static func makeDownloadProgressHandler() -> @Sendable (DownloadProgress) -> Void {
        { p in
            var line = "\rDownloading \(p.modelId) [\(p.filesCompleted)/\(p.filesTotal)]"
            if let total = p.bytesTotal {
                let pct = Int(Double(p.bytesCompleted) / Double(max(1, total)) * 100)
                line += "  \(formatBytes(p.bytesCompleted))/\(formatBytes(total)) (\(pct)%)"
            }
            else {
                line += "  \(formatBytes(p.bytesCompleted))"
            }
            if let bps = p.bytesPerSecond, bps > 0 {
                line += "  \(formatBytes(Int64(bps)))/s"
            }
            if p.currentFile.isEmpty == false {
                let short = (p.currentFile as NSString).lastPathComponent
                line += "  \(short)"
            }
            let data = Data((line + "  \u{1B}[K").utf8)
            FileHandle.standardError.write(data)
        }
    }
}
