import ArgumentParser
import Foundation
import SuperscribeKit

struct ModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "model",
        abstract: "List, refresh, or set defaults for transcription models."
    )

    @Option(name: .long, help: "Backend (parakeet, whisper.cpp). Defaults to your configured backend.")
    var backend: Backend?

    @Flag(name: .long, help: "List models. Implicit when no other verb is given.")
    var list: Bool = false

    @Option(name: .customLong("set-default"), help: "Set the default model id for the backend.")
    var setDefault: String?

    @Flag(name: .long, help: "With --list: show the remote catalog (cached). Without: refresh first.")
    var remote: Bool = false

    @Flag(name: .long, help: "Re-fetch the remote catalog for the backend, updating the cache.")
    var refresh: Bool = false

    @Option(name: .long, help: "Download a model by id (e.g. v3, large-v3_turbo).")
    var download: String?

    @Option(name: .long, help: "Remove an installed model by id.")
    var rm: String?

    @Flag(name: .long, help: "Skip confirmation prompts (use with --rm).")
    var yes: Bool = false

    @Flag(name: .long, help: "Emit machine-readable JSON (only with --list).")
    var json: Bool = false

    mutating func validate() throws {
        try assertMutuallyExclusive([
            ("--list", list),
            ("--set-default", setDefault != nil),
            ("--download", download != nil),
            ("--rm", rm != nil)
        ])
        if (download != nil || rm != nil) && refresh == true {
            throw ValidationError("--refresh cannot be combined with --download or --rm.")
        }
        if remote == true && (setDefault != nil || download != nil || rm != nil) {
            throw ValidationError("--remote applies only to --list.")
        }
        if json == true && (setDefault != nil || download != nil || rm != nil) {
            throw ValidationError("--json applies only to --list.")
        }
    }

    mutating func run() async throws {
        let backend = BackendManager.resolveBackend(cliBackend: backend)

        if let modelId = download {
            try await runDownload(modelId, backend: backend)
            return
        }
        if let modelId = rm {
            try runRemove(modelId, backend: backend)
            return
        }
        if let modelId = setDefault {
            try await runSetDefault(modelId, backend: backend)
            return
        }
        if refresh == true && list == false {
            try await runRefresh(backend: backend)
            return
        }
        // Default verb is --list (with optional --remote and/or --refresh).
        try await runList(backend: backend)
    }

    // MARK: - Verbs

    private func runList(backend: Backend) async throws {
        if remote == true {
            let (entry, refreshed) = try await ModelManager.catalog(for: backend, forceRefresh: refresh)
            let installed = (try? ModelManager.installedModels(for: backend)) ?? []
            let installedIds = Set(installed.map(\.id))
            if json == true {
                printJSON(entry.models)
            }
            else {
                renderRemoteList(
                    entry,
                    installedIds: installedIds,
                    backend: backend,
                    refreshed: refreshed
                )
            }
            return
        }

        // Local install scan.
        let installed = try ModelManager.installedModels(for: backend)
        if json == true {
            printJSON(installed)
        }
        else {
            renderInstalledList(installed, backend: backend)
        }
    }

    private func runRefresh(backend: Backend) async throws {
        let (entry, _) = try await ModelManager.catalog(for: backend, forceRefresh: true)
        print(
            "Refreshed \(backend.rawValue) catalog: \(entry.models.count) model(s), fetched \(formatDate(entry.fetchedAt))."
        )
    }

    private func runDownload(_ modelId: String, backend: Backend) async throws {
        let installPath = try ModelInstaller.installPath(for: modelId, backend: backend)
        if ModelInstaller.isInstalled(at: installPath, backend: backend) == true {
            print("Already installed at \(installPath.path)")
            return
        }
        // Always refresh before downloading to avoid stale repoId / repoURL
        // from a previously cached catalog entry.
        let (entry, _) = try await ModelManager.catalog(for: backend, forceRefresh: true)
        guard let info = entry.models.first(where: { $0.id == modelId }) else {
            throw ModelInstallationError.unknownModel(
                model: modelId,
                backend: backend,
                available: entry.models.map(\.id)
            )
        }
        let final = try await ModelInstaller.install(
            model: info,
            backend: backend,
            onProgress: ModelManager.makeDownloadProgressHandler()
        )
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
        print("Installed at \(final.path)")
    }

    private func runRemove(_ modelId: String, backend: Backend) throws {
        let installed = (try? ModelManager.installedModels(for: backend)) ?? []
        guard installed.contains(where: { $0.id == modelId }) == true else {
            let valid = installed.map(\.id).joined(separator: ", ")
            throw ValidationError(
                "Model '\(modelId)' is not installed for backend '\(backend.rawValue)'. "
                    + "Installed: \(valid.isEmpty ? "(none)" : valid)"
            )
        }
        let paths = try ModelInstaller.removalPaths(modelId: modelId, backend: backend)
        if paths.isEmpty == true {
            throw ValidationError(
                "Model '\(modelId)' has no files to remove for backend '\(backend.rawValue)'."
            )
        }
        if yes == false {
            let listing = paths.map(\.path).joined(separator: "\n  ")
            guard confirm(prompt: "Remove '\(modelId)'?\n  \(listing)\n[y/N] ", skip: false) == true else {
                print("Aborted.")
                return
            }
        }
        try ModelInstaller.removeInstalled(modelId: modelId, backend: backend)
        for path in paths {
            print("Removed \(path.path)")
        }
    }

    private func runSetDefault(_ modelId: String, backend: Backend) async throws {
        let (entry, _) = try await ModelManager.catalog(for: backend, forceRefresh: false)
        guard entry.models.contains(where: { $0.id == modelId }) == true else {
            let valid = entry.models.map(\.id).joined(separator: ", ")
            throw ValidationError(
                "Unknown model '\(modelId)' for backend '\(backend.rawValue)'. Available: \(valid)"
            )
        }
        var config = UserConfig.load()
        config.setDefaultModel(modelId, for: backend)
        try config.save()
        print("Default model for '\(backend.rawValue)' set to '\(modelId)'.")
    }

    // MARK: - Rendering

    private func renderInstalledList(_ models: [InstalledModelInfo], backend: Backend) {
        let userDefault = UserConfig.load().defaultModel(for: backend)
        let builtinDefault = BackendManager.builtInDefaultModel(for: backend)
        if models.isEmpty == true {
            print("No models installed for backend '\(backend.rawValue)'.")
            print("Try: superscribe model --list --remote --backend \(backend.rawValue)")
            return
        }
        let idWidth = max(8, models.map(\.id.count).max() ?? 0)
        for m in models {
            let marker = defaultMarker(
                id: m.id, userDefault: userDefault, builtinDefault: builtinDefault
            )
            let size = m.sizeBytes.map(formatBytes) ?? "—"
            let paddedId = m.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
            print("  \(paddedId)  \(size.leftPad(toLength: 10))  \(m.path.path)\(marker)")
        }
    }

    private func renderRemoteList(
        _ entry: CatalogEntry,
        installedIds: Set<String>,
        backend: Backend,
        refreshed: Bool
    ) {
        let userDefault = UserConfig.load().defaultModel(for: backend)
        let builtinDefault = BackendManager.builtInDefaultModel(for: backend)
        if entry.models.isEmpty == true {
            print("Remote catalog for '\(backend.rawValue)' is empty.")
            return
        }
        let idWidth = max(8, entry.models.map(\.id.count).max() ?? 0)
        for m in entry.models {
            let marker = defaultMarker(
                id: m.id, userDefault: userDefault, builtinDefault: builtinDefault
            )
            let installedTag = installedIds.contains(m.id) ? " (installed)" : ""
            let size = m.totalSizeBytes.map(formatBytes) ?? "—"
            let updated = m.lastModified.map(formatDate) ?? "—"
            let paddedId = m.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
            print("  \(paddedId)  \(size.leftPad(toLength: 10))  \(updated)\(installedTag)\(marker)")
        }
        let stamp = formatDate(entry.fetchedAt)
        let suffix = refreshed ? " (refreshed)" : ""
        print("\nfetched \(stamp)\(suffix)")
    }

    private func defaultMarker(
        id: String, userDefault: String?, builtinDefault: String
    ) -> String {
        if userDefault == id { return "  (user default)" }
        if userDefault == nil && id == builtinDefault { return "  (default)" }
        return ""
    }

    private func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONCoding.catalogEncoder()
        if let data = try? encoder.encode(value),
            let s = String(data: data, encoding: .utf8)
        {
            print(s)
        }
    }
}
