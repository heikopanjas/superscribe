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
