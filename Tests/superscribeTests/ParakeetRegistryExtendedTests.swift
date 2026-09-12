import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Parakeet registry

@Suite("ParakeetBackend registry extended", .serialized, ResetSharedStateTrait())
struct ParakeetRegistryExtendedTests {
    @Test func unknownIdHuggingFaceRepoId() -> Void {
        #expect(throws: UnsupportedModelError.self) { _ = try ParakeetBackend.huggingFaceRepoId(for: "custom-model") }
    }

    @Test func repoFolderNameMatchesInstallFolder() throws -> Void {
        #expect(try ParakeetBackend.installFolderName(for: "v3") == ParakeetBackend.installFolderName(for: "v3"))
    }

    @Test func installedModelsFindsMlmodelcBundle() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try TestHelpers.makeParakeetInstallation(at: folder)
            let models = try ParakeetBackend.installedModels()
            #expect(models.count == 1)
            if models.count == 1 {
                #expect(models[0].id == "v3")
                #expect((models[0].sizeBytes ?? 0) > 0)
            }
        }
    }

    @Test func ensureLoadedUsesTestHook() async throws -> Void {
        let prior = ParakeetBackend.testLoadHook
        defer { ParakeetBackend.testLoadHook = prior }
        ParakeetBackend.testLoadHook = {
            MockParakeetSession(
                result: ASRResult(
                    text: "ok",
                    confidence: 1,
                    duration: 0.1,
                    processingTime: 0.01,
                    tokenTimings: nil
                )
            )
        }
        let backend = try ParakeetBackend(model: "v3", injectedSession: nil)
        let out = try await backend.transcribe(
            samples: [0.1],
            segment: SpeechSegment(start: 0, end: 1),
            config: TranscriptionConfig(language: nil, prompt: nil)
        )
        #expect(out.words.count == 1)
    }

    @Test func installedModelsOmitsUnknownFolder() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("custom-unknown-model", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("X.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            let models = try ParakeetBackend.installedModels()
            #expect(models.contains(where: { $0.id == "custom-unknown-model" }) == false)
        }
    }

    @Test func publicRemoteModelsUsesSharedSessionOverride() async throws -> Void {
        let payload = """
            [{"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z"}]
            """
        let prior = ParakeetBackend.overrideRemoteModelsSession
        defer { ParakeetBackend.overrideRemoteModelsSession = prior }
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models?") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                let info = """
                    {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z","siblings":[]}
                    """
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(info.utf8))
            },
            { session in
                ParakeetBackend.overrideRemoteModelsSession = session
                let models = try await ParakeetBackend.remoteModels()
                #expect(models.isEmpty == false)
            }
        )
    }

    @Test func fetchRepoSizesUsesDefaultRepoInfoClosure() async throws -> Void {
        let repos = [HuggingFaceHub.HFRepo(id: "FluidInference/parakeet-tdt-0.6b-v3-coreml", lastModified: nil)]
        let info = """
            {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":null,"siblings":[
              {"rfilename":"a.bin","size":10}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(info.utf8))
            },
            { session in
                let sizes = try await ParakeetBackend.fetchRepoSizes(
                    for: repos,
                    session: session
                )
                #expect(sizes.count == 1)
            }
        )
    }

}
