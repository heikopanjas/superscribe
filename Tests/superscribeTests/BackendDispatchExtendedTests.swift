import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Backend dispatch

@Suite("Backend dispatch extended", .serialized, ResetSharedStateTrait())
struct BackendDispatchExtendedTests {
    @Test func makeTranscriberWhisperOnArm64() throws -> Void {
        #if arch(arm64)
        let t = try Backend.whisperCpp.makeTranscriber(model: "tiny")
        #expect(t.capabilities.defaultModelId == WhisperBackend.defaultModelId)
        #else
        #expect(Bool(false))
        #endif
    }

    @Test func appleSpeechRemoteModelsEmptyWhenUnavailable() async throws -> Void {
        let prior = AppleSpeechSupport.testForceRuntimeUnavailable
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        defer { AppleSpeechSupport.testForceRuntimeUnavailable = prior }
        #expect(try await Backend.appleSpeech.remoteModels().isEmpty == true)
    }

    @Test func parakeetInstalledModelsEmptyWhenCacheMissing() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            #expect(FileManager.default.fileExists(atPath: parakeetRoot.path) == true)
            let models = try await Backend.parakeet.installedModels()
            #expect(models.isEmpty == true)
        }
    }

    @Test func whisperInstalledModelsFromTempBins() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { _, whisperRoot in
            try FileManager.default.createDirectory(at: whisperRoot, withIntermediateDirectories: true)
            let bin = whisperRoot.appendingPathComponent("demo.bin")
            try Data("x".utf8).write(to: bin)
            let models = try await Backend.whisperCpp.installedModels()
            #expect(models.contains(where: { $0.id == "demo" }) == true)
        }
    }

    @Test func parakeetRemoteModelsViaMock() async throws -> Void {
        let payload = """
            [{"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z"}]
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models?") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml") == true {
                    let info = """
                        {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z","siblings":[
                          {"rfilename":"model.mlmodelc/x","size":100}
                        ]}
                        """
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(info.utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let session = session
                let models = try await ParakeetBackend.remoteModels(session: session)
                #expect(models.isEmpty == false)
                #expect(models.contains(where: { $0.id == "v3" }) == true)
                _ = session
            }
        )
    }

    @Test func whisperRemoteModelsViaMock() async throws -> Void {
        let info = """
            {"id":"ggerganov/whisper.cpp","lastModified":"2024-01-01T00:00:00Z","siblings":[
              {"rfilename":"ggml-tiny.bin","size":1000}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(info.utf8))
            },
            { session in
                let models = try await WhisperBackend.remoteModels(session: session)
                #expect(models.contains(where: { $0.id == "tiny" }) == true)
            }
        )
    }
}
