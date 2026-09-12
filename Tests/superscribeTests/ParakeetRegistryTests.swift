import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ParakeetBackend.mapRepos", .serialized, ResetSharedStateTrait())
struct ParakeetRegistryTests {

    @Test func mapsKnownRepoIdsToShortAliases() throws -> Void {
        let repos: [HuggingFaceHub.HFRepo] = [
            .init(id: "FluidInference/parakeet-tdt-0.6b-v3-coreml", lastModified: nil),
            .init(id: "FluidInference/parakeet-tdt-0.6b-v2-coreml", lastModified: nil),
            .init(id: "FluidInference/parakeet-tdt-ctc-110m-coreml", lastModified: nil),
            .init(id: "FluidInference/parakeet-0.6b-ja-coreml", lastModified: nil)
        ]
        let result = try ParakeetBackend.mapRepos(repos)
        let ids = result.map(\.id)
        #expect(ids.contains("v2"))
        #expect(ids.contains("v3"))
        #expect(ids.contains("tdt-ctc-110m"))
        #expect(ids.contains("tdt-ja"))
    }

    @Test func omitsUnsupportedRepos() throws -> Void {
        let repos: [HuggingFaceHub.HFRepo] = [
            .init(id: "FluidInference/parakeet-tdt-future-coreml", lastModified: nil)
        ]
        let result = try ParakeetBackend.mapRepos(repos)
        #expect(result.isEmpty == true)
    }

    @Test func appliesSizeInfoWhenProvided() throws -> Void {
        let repos: [HuggingFaceHub.HFRepo] = [
            .init(id: "FluidInference/parakeet-tdt-0.6b-v3-coreml", lastModified: nil)
        ]
        let sizes: [String: (totalBytes: Int64?, fileCount: Int?)] = [
            "FluidInference/parakeet-tdt-0.6b-v3-coreml": (123_456_789, 7)
        ]
        let result = try ParakeetBackend.mapRepos(repos, sizes: sizes)
        #expect(result[0].id == "v3")
        #expect(result[0].totalSizeBytes == 123_456_789)
        #expect(result[0].fileCount == 7)
    }

    @Test func fetchRepoSizesCapsConcurrency() async throws -> Void {
        let repos = (0 ..< 8).map { index in
            HuggingFaceHub.HFRepo(
                id: "FluidInference/parakeet-repo-\(index)",
                lastModified: nil
            )
        }
        let gate = ConcurrentTestGate(batchSize: 2)
        let maxConcurrent = 2

        _ = try await ParakeetBackend.fetchRepoSizes(
            for: repos,
            maxConcurrent: maxConcurrent
        ) { repoId in
            await gate.enter()
            await gate.leave()
            return HuggingFaceHub.HFRepoInfo(id: repoId, siblings: [])
        }

        #expect(await gate.peak <= maxConcurrent)
        #expect(await gate.peak == maxConcurrent)
        #expect(await gate.current == 0)
    }
}
