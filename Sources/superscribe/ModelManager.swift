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
        try await backend.remoteModels()
    }

    /// Backend → its `installedModels()` static call.
    static func installedModels(for backend: Backend) throws -> [InstalledModelInfo] {
        try backend.installedModels()
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
    ///
    /// Every column has a fixed character width so the line never reflows as
    /// values grow or shrink. The line is cleared with `ESC[2K` before each
    /// write to wipe any leftover characters from a previous, longer render.
    static func makeDownloadProgressHandler() -> @Sendable (DownloadProgress) -> Void {
        { p in
            let rate: String = {
                if let bps = p.bytesPerSecond, bps > 0 {
                    return "\(formatBytes(Int64(bps)))/s"
                }
                return "--/s"
            }()
            let bytes: String = {
                if let total = p.bytesTotal {
                    return "\(formatBytes(p.bytesCompleted))/\(formatBytes(total))"
                }
                return formatBytes(p.bytesCompleted)
            }()
            let pct: String = {
                if let total = p.bytesTotal {
                    let v = Int(Double(p.bytesCompleted) / Double(max(1, total)) * 100)
                    return "(\(v)%)"
                }
                return ""
            }()
            let counter = "[\(p.filesCompleted)/\(p.filesTotal)]"
            let file: String = {
                if p.currentFile.isEmpty == true { return "" }
                let short = (p.currentFile as NSString).lastPathComponent
                return truncateMiddle(short, max: 32)
            }()

            // Fixed slot widths (chosen for the largest realistic value).
            //   rate     12  e.g. "1023.0 MiB/s"
            //   bytes    23  e.g. "1023.0 MiB/1023.0 MiB"
            //   pct       6  e.g. "(100%)"
            //   counter   7  e.g. "[99/99]"
            //   modelId  24
            //   file     32
            var line = "\r\u{1B}[2KDownloading"
            line += "  " + rate.leftPad(toLength: 12)
            line += "  " + bytes.leftPad(toLength: 23)
            line += "  " + pct.leftPad(toLength: 6)
            line += "  " + counter.leftPad(toLength: 7)
            line += "  " + p.modelId.rightPad(toLength: 24)
            line += "  " + file.rightPad(toLength: 32)
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    /// Truncates `s` to at most `max` characters by replacing the middle
    /// with `…`. Preserves a useful prefix and the file extension.
    private static func truncateMiddle(_ s: String, max: Int) -> String {
        guard s.count > max, max > 3 else { return s }
        let keep = max - 1  // for the ellipsis
        let head = keep / 2
        let tail = keep - head
        let prefix = s.prefix(head)
        let suffix = s.suffix(tail)
        return "\(prefix)…\(suffix)"
    }
}
