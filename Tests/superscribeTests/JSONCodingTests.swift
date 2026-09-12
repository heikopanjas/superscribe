import Foundation
import Testing

@testable import SuperscribeKit

@Suite("JSONCoding", .serialized, ResetSharedStateTrait())
struct JSONCodingTests {
    @Test func catalogRoundTripPreservesISO8601Dates() throws -> Void {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let catalog = Catalog(
            entries: [
                Backend.parakeet.rawValue: CatalogEntry(
                    fetchedAt: fetchedAt,
                    models: [
                        RemoteModelInfo(
                            id: "v3",
                            repoId: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
                            totalSizeBytes: 100,
                            fileCount: 1,
                            lastModified: fetchedAt,
                            repoURL: (try #require(URL(string: "https://huggingface.co/x")))
                        )
                    ]
                )
            ]
        )

        let data = try JSONCoding.catalogEncoder().encode(catalog)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"version\""))
        #expect(json.contains("\"entries\""))

        let decoded = try JSONCoding.catalogDecoder().decode(Catalog.self, from: data)
        #expect(decoded.entries.count == 1)
        let entry = try #require(decoded.entry(for: .parakeet))
        #expect(abs(entry.fetchedAt.timeIntervalSince1970 - fetchedAt.timeIntervalSince1970) < 1)
    }

    @Test func configEncoderOmitsDateStrategy() throws -> Void {
        struct Payload: Codable { let key: String }
        let data = try JSONCoding.configEncoder().encode(Payload(key: "value"))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"key\""))
        #expect(json.contains("value"))
    }

    @Test func transcriptEncoderUsesUnescapedSlashes() throws -> Void {
        let encoder = JSONCoding.transcriptEncoder()
        #expect(encoder.outputFormatting.contains(.withoutEscapingSlashes))
    }
}
