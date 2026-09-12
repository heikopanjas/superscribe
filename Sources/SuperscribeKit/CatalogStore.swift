import Foundation

/// Reads and writes the shared catalog file.
public enum CatalogStore {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var overrideURL: URL?
    }

    /// Override for testing; nil means use the user's real cache directory.
    internal static var overrideURL: URL? {
        get { return Self.testState[\.overrideURL] }
        set { Self.testState[\.overrideURL] = newValue }
    }

    public static var fileURL: URL {
        if let overrideURL = Self.overrideURL { return overrideURL }
        return Self.defaultCacheDirectory().appendingPathComponent("catalog.json")
    }

    static func defaultCacheDirectory() -> URL {
        return SuperscribePaths.catalogCacheDirectory()
    }

    /// Loads the catalog from disk. Returns an empty catalog if the file is
    /// missing. Throws if the file exists but cannot be parsed.
    public static func load() throws -> Catalog {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) == true else {
            return Catalog()
        }
        let data = try Data(contentsOf: url)
        return try JSONCoding.catalogDecoder().decode(Catalog.self, from: data)
    }

    /// Atomically writes the catalog to disk, creating parent directories
    /// as needed.
    public static func save(_ catalog: Catalog) throws -> Void {
        let url = Self.fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONCoding.catalogEncoder().encode(catalog)
        try data.write(to: url, options: .atomic)
    }

    /// Convenience: load → mutate one entry → save.
    public static func update(_ entry: CatalogEntry, for backend: Backend) throws -> Void {
        try FileTransaction.withLock(for: Self.fileURL) {
            var catalog = try Self.load()
            catalog.update(entry, for: backend)
            try Self.save(catalog)
        }
    }
    public static func updateAsync(_ entry: CatalogEntry, for backend: Backend) async throws -> Void {
        let dependencies = Self.testState
        let locks = FileTransaction.lockOperation
        try await FileTransaction.worker.run { _ in
            try Self.$testState.withValue(dependencies) {
                try FileTransaction.$lockOperation.withValue(locks) { try Self.update(entry, for: backend) }
            }
        }
    }

}
