import Foundation

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
        return self.entries[backend.rawValue]
    }

    public mutating func update(_ entry: CatalogEntry, for backend: Backend) -> Void {
        self.entries[backend.rawValue] = entry
        return
    }
}
