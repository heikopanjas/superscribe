import Foundation

/// One backend's entry inside the on-disk model catalog.
public struct CatalogEntry: Sendable, Codable, Hashable {
    public let fetchedAt: Date
    public let models: [RemoteModelInfo]

    public init(fetchedAt: Date, models: [RemoteModelInfo]) {
        self.fetchedAt = fetchedAt
        self.models = models
    }
}

/// On-disk model catalog persisted at `~/.cache/superscribe/catalog.json`.
///
/// Schema:
/// ```json
/// {
///   "version": 1,
///   "entries": { "<backend>": { "fetchedAt": <ISO date>, "models": [...] } }
/// }
/// ```
///
/// Unknown backends are preserved on round-trip so older binaries don't
/// destroy entries written by newer ones.
public struct Catalog: Sendable, Codable {
    public static let currentVersion = 1

    public var version: Int
    public var entries: [String: CatalogEntry]

    public init(version: Int = Catalog.currentVersion, entries: [String: CatalogEntry] = [:]) {
        self.version = version
        self.entries = entries
    }

    public func entry(for backend: Backend) -> CatalogEntry? {
        entries[backend.rawValue]
    }

    public mutating func update(_ entry: CatalogEntry, for backend: Backend) {
        entries[backend.rawValue] = entry
    }
}

/// Reads and writes the shared catalog file.
public enum CatalogStore {
    /// Override for testing; nil means use the user's real cache directory.
    nonisolated(unsafe) static var overrideURL: URL?

    public static var fileURL: URL {
        if let overrideURL { return overrideURL }
        return defaultCacheDirectory().appendingPathComponent("catalog.json")
    }

    static func defaultCacheDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/superscribe", isDirectory: true)
    }

    /// Loads the catalog from disk. Returns an empty catalog if the file is
    /// missing. Throws if the file exists but cannot be parsed.
    public static func load() throws -> Catalog {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Catalog()
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Catalog.self, from: data)
    }

    /// Atomically writes the catalog to disk, creating parent directories
    /// as needed.
    public static func save(_ catalog: Catalog) throws {
        let url = fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        try data.write(to: url, options: .atomic)
    }

    /// Convenience: load → mutate one entry → save.
    public static func update(_ entry: CatalogEntry, for backend: Backend) throws {
        var catalog = (try? load()) ?? Catalog()
        catalog.update(entry, for: backend)
        try save(catalog)
    }
}
