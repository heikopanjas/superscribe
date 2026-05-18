import Foundation
import Testing

@testable import SuperscribeKit

@Suite("CatalogStore", .serialized)
struct CatalogStoreTests {

    /// Sets up a temp catalog file path for the duration of the test.
    private func withTempCatalog<T>(_ body: () throws -> T) throws -> T {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscribe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("catalog.json")
        let prior = CatalogStore.overrideURL
        CatalogStore.overrideURL = url
        defer {
            CatalogStore.overrideURL = prior
            try? FileManager.default.removeItem(at: tmp)
        }
        return try body()
    }

    private func sampleEntry() -> CatalogEntry {
        CatalogEntry(
            fetchedAt: Date(timeIntervalSince1970: 1_000_000),
            models: [
                RemoteModelInfo(
                    id: "v3",
                    repoId: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
                    totalSizeBytes: 12345,
                    fileCount: 4,
                    lastModified: Date(timeIntervalSince1970: 999_000),
                    repoURL: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!
                )
            ]
        )
    }

    @Test func loadReturnsEmptyWhenFileMissing() throws {
        try withTempCatalog {
            let catalog = try CatalogStore.load()
            #expect(catalog.entries.isEmpty)
            #expect(catalog.version == Catalog.currentVersion)
        }
    }

    @Test func saveAndLoadRoundTrip() throws {
        try withTempCatalog {
            var catalog = Catalog()
            catalog.update(sampleEntry(), for: .parakeet)
            try CatalogStore.save(catalog)

            let loaded = try CatalogStore.load()
            let entry = try #require(loaded.entry(for: .parakeet))
            #expect(entry.models.count == 1)
            #expect(entry.models[0].id == "v3")
            #expect(entry.models[0].totalSizeBytes == 12345)
        }
    }

    @Test func updateConvenienceMergesEntry() throws {
        try withTempCatalog {
            try CatalogStore.update(sampleEntry(), for: .parakeet)
            try CatalogStore.update(
                CatalogEntry(fetchedAt: Date(), models: []), for: .whisperCpp
            )
            let loaded = try CatalogStore.load()
            #expect(loaded.entries.count == 2)
            #expect(loaded.entry(for: .parakeet) != nil)
            #expect(loaded.entry(for: .whisperCpp) != nil)
        }
    }

    @Test func toleratesUnknownFutureBackendKeys() throws {
        try withTempCatalog {
            // Hand-written JSON containing a future backend key not in our enum.
            let json = """
                {
                  "version": 1,
                  "entries": {
                    "parakeet": {
                      "fetchedAt": "1970-01-12T13:46:40Z",
                      "models": []
                    },
                    "futureBackend": {
                      "fetchedAt": "1970-01-12T13:46:40Z",
                      "models": []
                    }
                  }
                }
                """
            try json.data(using: .utf8)!.write(to: CatalogStore.fileURL)

            let loaded = try CatalogStore.load()
            // Both keys preserved (entries is just a [String: CatalogEntry]).
            #expect(loaded.entries.count == 2)
            #expect(loaded.entry(for: .parakeet) != nil)
            // entry(for:) ignores the unknown key — that's the intended behavior.
        }
    }
}
