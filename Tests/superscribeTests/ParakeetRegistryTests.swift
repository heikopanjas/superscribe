import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ParakeetBackend.mapRepos")
struct ParakeetRegistryTests {

    @Test func mapsKnownRepoIdsToShortAliases() {
        let repos: [HuggingFaceHub.HFRepo] = [
            .init(id: "FluidInference/parakeet-tdt-0.6b-v3-coreml", lastModified: nil),
            .init(id: "FluidInference/parakeet-tdt-0.6b-v2-coreml", lastModified: nil),
            .init(id: "FluidInference/parakeet-tdt-ctc-110m-coreml", lastModified: nil),
            .init(id: "FluidInference/parakeet-0.6b-ja-coreml", lastModified: nil)
        ]
        let result = ParakeetBackend.mapRepos(repos)
        let ids = result.map(\.id)
        #expect(ids.contains("v2"))
        #expect(ids.contains("v3"))
        #expect(ids.contains("tdt-ctc-110m"))
        #expect(ids.contains("tdt-ja"))
    }

    @Test func passesUnknownRepoNamesThrough() {
        let repos: [HuggingFaceHub.HFRepo] = [
            .init(id: "FluidInference/parakeet-tdt-future-coreml", lastModified: nil)
        ]
        let result = ParakeetBackend.mapRepos(repos)
        #expect(result.count == 1)
        #expect(result[0].id == "parakeet-tdt-future-coreml")
        #expect(result[0].repoId == "FluidInference/parakeet-tdt-future-coreml")
    }

    @Test func appliesSizeInfoWhenProvided() {
        let repos: [HuggingFaceHub.HFRepo] = [
            .init(id: "FluidInference/parakeet-tdt-0.6b-v3-coreml", lastModified: nil)
        ]
        let sizes: [String: (totalBytes: Int64?, fileCount: Int?)] = [
            "FluidInference/parakeet-tdt-0.6b-v3-coreml": (123_456_789, 7)
        ]
        let result = ParakeetBackend.mapRepos(repos, sizes: sizes)
        #expect(result[0].id == "v3")
        #expect(result[0].totalSizeBytes == 123_456_789)
        #expect(result[0].fileCount == 7)
    }
}
