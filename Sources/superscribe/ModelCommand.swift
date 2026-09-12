import ArgumentParser
import Foundation
import SuperscribeKit

struct ModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "model",
        abstract: "List, refresh, or set defaults for transcription models."
    )

    @Option(name: .long, help: "Backend (parakeet, whisper.cpp, appleSpeech). Defaults to your configured backend.")
    var backend: Backend?

    @Flag(name: .long, help: "List models. Implicit when no other verb is given.")
    var list: Bool = false

    @Option(name: .customLong("set-default"), help: "Set the default model id for the backend.")
    var setDefault: String?

    @Flag(name: .long, help: "With --list: show the remote catalog (cached). Without: refresh first.")
    var remote: Bool = false

    @Flag(name: .long, help: "Re-fetch the remote catalog for the backend, updating the cache.")
    var refresh: Bool = false

    @Option(name: .long, help: "Download a model by id (e.g. v3, large-v3-turbo, en-US).")
    var download: String?

    @Option(name: .long, help: "Remove an installed model by id.")
    var rm: String?

    @Flag(name: .long, help: "Skip confirmation prompts (use with --rm).")
    var yes: Bool = false

    @Flag(name: .long, help: "Emit machine-readable JSON (only with --list).")
    var json: Bool = false

    mutating func validate() throws -> Void {
        try assertMutuallyExclusive([
            ("--list", self.list),
            ("--set-default", self.setDefault != nil),
            ("--download", self.download != nil),
            ("--rm", self.rm != nil)
        ])
        if (self.download != nil || self.rm != nil || self.setDefault != nil) && self.refresh == true {
            throw ValidationError("--refresh cannot be combined with --download, --rm, or --set-default.")
        }
        if self.yes == true && self.rm == nil { throw ValidationError("--yes requires --rm.") }
        if self.refresh == true && self.list == true && self.remote == false { throw ValidationError("--refresh with --list requires --remote.") }
        if self.refresh == true && self.json == true && self.remote == false { throw ValidationError("--json with --refresh requires --remote.") }
        if self.remote == true && (self.setDefault != nil || self.download != nil || self.rm != nil) {
            throw ValidationError("--remote applies only to --list.")
        }
        if self.json == true && (self.setDefault != nil || self.download != nil || self.rm != nil) {
            throw ValidationError("--json applies only to --list.")
        }
    }

    mutating func run() async throws -> Void {
        let backend = try BackendManager.resolveBackend(cliBackend: self.backend)

        if let modelId = self.download {
            try await self.runDownload(modelId, backend: backend)
            return
        }
        if let modelId = self.rm {
            try await self.runRemove(modelId, backend: backend)
            return
        }
        if let modelId = self.setDefault {
            try await self.runSetDefault(modelId, backend: backend)
            return
        }
        if self.refresh == true && self.list == false && self.remote == false {
            try await self.runRefresh(backend: backend)
            return
        }
        // Default verb is --list (with optional --remote and/or --refresh).
        try await self.runList(backend: backend)
    }

    // MARK: - Verbs

    private func runList(backend: Backend) async throws -> Void {
        if self.remote == true {
            let (entry, refreshed) = try await ModelManager.catalog(for: backend, forceRefresh: self.refresh || self.list == false)
            let installed = (try? await ModelManager.installedModels(for: backend)) ?? []
            let installedIds = Set(installed.map(\.id))
            if self.json == true {
                try self.printJSON(entry.models)
            }
            else {
                try self.renderRemoteList(
                    entry,
                    installedIds: installedIds,
                    backend: backend,
                    refreshed: refreshed
                )
            }
            return
        }

        // Local install scan.
        let installed = try await ModelManager.installedModels(for: backend)
        if self.json == true {
            try self.printJSON(installed)
        }
        else {
            try self.renderInstalledList(installed, backend: backend)
        }
    }

    private func runRefresh(backend: Backend) async throws -> Void {
        let (entry, _) = try await ModelManager.catalog(for: backend, forceRefresh: true)
        print(
            "Refreshed \(backend.rawValue) catalog: \(entry.models.count) model(s), fetched \(formatDate(entry.fetchedAt))."
        )
    }

    private func runDownload(_ modelId: String, backend: Backend) async throws -> Void {
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

    private func runRemove(_ modelId: String, backend: Backend) async throws -> Void {
        let installed = (try? await ModelManager.installedModels(for: backend)) ?? []
        guard installed.contains(where: { $0.id == modelId }) == true else {
            let valid = installed.map(\.id).joined(separator: ", ")
            throw ValidationError(
                "Model '\(modelId)' is not installed for backend '\(backend.rawValue)'. "
                    + "Installed: \(valid.isEmpty ? "(none)" : valid)"
            )
        }
        let paths = try await ModelInstaller.removalPaths(modelId: modelId, backend: backend)
        if paths.isEmpty == true {
            throw ValidationError(
                "Model '\(modelId)' has no files to remove for backend '\(backend.rawValue)'."
            )
        }
        if self.yes == false {
            let listing = paths.map(\.path).joined(separator: "\n  ")
            guard confirm(prompt: "Remove '\(modelId)'?\n  \(listing)\n[y/N] ", skip: false) == true else {
                print("Aborted.")
                return
            }
        }
        try await ModelInstaller.removeInstalled(modelId: modelId, backend: backend)
        for path in paths {
            print(backend == .appleSpeech ? "Released reservation for \(modelId)" : "Removed \(path.path)")
        }
    }

    private func runSetDefault(_ modelId: String, backend: Backend) async throws -> Void {
        let (entry, _) = try await ModelManager.catalog(for: backend, forceRefresh: false)
        guard entry.models.contains(where: { $0.id == modelId }) == true else {
            let valid = entry.models.map(\.id).joined(separator: ", ")
            throw ValidationError(
                "Unknown model '\(modelId)' for backend '\(backend.rawValue)'. Available: \(valid)"
            )
        }
        try await UserConfig.update { $0.setDefaultModel(modelId, for: backend) }
        print("Default model for '\(backend.rawValue)' set to '\(modelId)'.")
    }

    // MARK: - Rendering

    private func renderInstalledList(_ models: [InstalledModelInfo], backend: Backend) throws -> Void {
        let userDefault = try UserConfig.load().defaultModel(for: backend)
        let builtinDefault = BackendManager.builtInDefaultModel(for: backend)
        if models.isEmpty == true {
            print("No models installed for backend '\(backend.rawValue)'.")
            print("Try: superscribe model --list --remote --backend \(backend.rawValue)")
            return
        }
        let idWidth = max(8, models.map(\.id.count).max() ?? 0)
        for m in models {
            let marker = self.defaultMarker(
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
    ) throws -> Void {
        let userDefault = try UserConfig.load().defaultModel(for: backend)
        let builtinDefault = BackendManager.builtInDefaultModel(for: backend)
        if entry.models.isEmpty == true {
            print("Remote catalog for '\(backend.rawValue)' is empty.")
            return
        }
        let idWidth = max(8, entry.models.map(\.id.count).max() ?? 0)
        for m in entry.models {
            let marker = self.defaultMarker(
                id: m.id, userDefault: userDefault, builtinDefault: builtinDefault
            )
            let installedTag =
                if installedIds.contains(m.id) == true { " (installed)" }
                else { "" }
            let size = m.totalSizeBytes.map(formatBytes) ?? "—"
            let updated = m.lastModified.map(formatDate) ?? "—"
            let paddedId = m.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
            print("  \(paddedId)  \(size.leftPad(toLength: 10))  \(updated)\(installedTag)\(marker)")
        }
        let stamp = formatDate(entry.fetchedAt)
        let suffix =
            if refreshed == true { " (refreshed)" }
            else { "" }
        print("\nfetched \(stamp)\(suffix)")
    }

    private func defaultMarker(
        id: String, userDefault: String?, builtinDefault: String
    ) -> String {
        if userDefault == id { return "  (user default)" }
        if userDefault == nil && id == builtinDefault { return "  (default)" }
        return ""
    }

    private func printJSON<T: Encodable>(_ value: T) throws -> Void {
        let data = try JSONCoding.catalogEncoder().encode(value)
        print(String(decoding: data, as: UTF8.self))
    }
}
