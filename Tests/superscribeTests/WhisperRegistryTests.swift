import Foundation
import Testing

@testable import SuperscribeKit

@Suite("WhisperBackend.filterGGMLSiblings")
struct WhisperRegistryTests {

    @Test func extractsGGMLBinFiles() {
        let siblings: [HuggingFaceHub.HFSibling] = [
            .init(rfilename: "ggml-base.bin", size: 100_000_000),
            .init(rfilename: "ggml-large-v3-turbo.bin", size: 1_500_000_000),
            // Encoder mlmodelc bundles must be ignored.
            .init(rfilename: "ggml-base.bin-encoder.mlmodelc/weights/weight.bin", size: 50_000_000),
            // Top-level non-ggml files must be ignored.
            .init(rfilename: "README.md", size: 42),
            .init(rfilename: "config.json", size: 256)
        ]

        let result = WhisperBackend.filterGGMLSiblings(siblings)
        let byId = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })

        #expect(result.count == 2)

        let base = try! #require(byId["base"])
        #expect(base.totalSizeBytes == 100_000_000)
        #expect(base.fileCount == 1)
        #expect(base.subpath == nil)
        #expect(base.repoId == WhisperBackend.huggingFaceRepoId)

        let turbo = try! #require(byId["large-v3-turbo"])
        #expect(turbo.totalSizeBytes == 1_500_000_000)
        #expect(turbo.fileCount == 1)
    }

    @Test func returnsEmptyWhenNoMatches() {
        #expect(WhisperBackend.filterGGMLSiblings([]).isEmpty)
        #expect(
            WhisperBackend.filterGGMLSiblings([
                .init(rfilename: "README.md", size: 100)
            ]).isEmpty
        )
    }

    @Test func handlesNilSizes() {
        let siblings: [HuggingFaceHub.HFSibling] = [
            .init(rfilename: "ggml-tiny.bin", size: nil)
        ]
        let result = WhisperBackend.filterGGMLSiblings(siblings)
        #expect(result.count == 1)
        #expect(result[0].id == "tiny")
        #expect(result[0].totalSizeBytes == nil)
    }

    @Test func resultsAreSortedById() {
        let siblings: [HuggingFaceHub.HFSibling] = [
            .init(rfilename: "ggml-tiny.bin", size: 1),
            .init(rfilename: "ggml-base.bin", size: 1),
            .init(rfilename: "ggml-medium.bin", size: 1)
        ]
        let result = WhisperBackend.filterGGMLSiblings(siblings)
        #expect(result.map(\.id) == ["base", "medium", "tiny"])
    }

    @Test func installPathUsesCacheDirectory() {
        let path = WhisperBackend.installPath(for: "large-v3-turbo")
        #expect(path.lastPathComponent == "large-v3-turbo.bin")
        #expect(path.path.contains("superscribe/whisper/large-v3-turbo.bin"))
    }

    @Test func defaultModelId() {
        #expect(WhisperBackend.defaultModelId == "large-v3-turbo")
    }
}
