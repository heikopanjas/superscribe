import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Backend dispatch", .serialized, ResetSharedStateTrait())
struct BackendDispatchTests {
    @Test func registryDefaultModelIds() {
        #expect(Backend.parakeet.registryDefaultModelId == ParakeetBackend.defaultModelId)
        #expect(Backend.whisperCpp.registryDefaultModelId == WhisperBackend.defaultModelId)
        #expect(Backend.appleSpeech.registryDefaultModelId.isEmpty == true)
    }

    @Test func installPathForWhisper() throws {
        let path = try Backend.whisperCpp.installPath(for: "base")
        #expect(path.lastPathComponent == "base.bin")
        #expect(path.path.contains("whisper"))
    }

    @Test func installPathForParakeet() throws {
        let path = try Backend.parakeet.installPath(for: "v3")
        #expect(path.lastPathComponent.contains("v3") || path.path.contains("v3"))
    }

    @Test func installPathForAppleSpeechThrows() {
        #expect(throws: ModelInstallationError.self) {
            _ = try Backend.appleSpeech.installPath(for: "any")
        }
    }

    @Test func installedModelsEmptyForAppleSpeech() throws {
        #expect(try Backend.appleSpeech.installedModels().isEmpty == true)
    }

    @Test func makeTranscriberReturnsParakeetOnArm64() throws {
        #if arch(arm64)
        let t = try Backend.parakeet.makeTranscriber(model: "v3")
        #expect(t.capabilities.defaultModelId == ParakeetBackend.defaultModelId)
        #else
        #expect(Bool(false), "Unexpected non-arm64 host")
        #endif
    }

    @Test func makeTranscriberAppleSpeechUnavailable() {
        #expect(throws: BackendTranscriberError.self) {
            _ = try Backend.appleSpeech.makeTranscriber(model: "")
        }
    }

    @Test func makeTranscriberParakeetUnavailableWhenForced() {
        let prior = ParakeetBackend.testForceUnavailable
        ParakeetBackend.testForceUnavailable = true
        defer { ParakeetBackend.testForceUnavailable = prior }
        #expect(throws: BackendTranscriberError.self) {
            _ = try Backend.parakeet.makeTranscriber(model: "v3")
        }
    }

    @Test func makeTranscriberWhisperUnavailableWhenForced() {
        let prior = WhisperBackend.testForceUnavailable
        WhisperBackend.testForceUnavailable = true
        defer { WhisperBackend.testForceUnavailable = prior }
        #expect(throws: BackendTranscriberError.self) {
            _ = try Backend.whisperCpp.makeTranscriber(model: "tiny")
        }
    }

    @Test func remoteModelsDispatchesToWhisper() async throws {
        let info = """
            {"id":"ggerganov/whisper.cpp","lastModified":"2024-01-01T00:00:00Z","siblings":[
              {"rfilename":"ggml-tiny.bin","size":1000}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(info.utf8))
            },
            { session in
                WhisperBackend.overrideRemoteModelsSession = session
                defer { WhisperBackend.overrideRemoteModelsSession = nil }
                let models = try await Backend.whisperCpp.remoteModels()
                #expect(models.contains(where: { $0.id == "tiny" }) == true)
            }
        )
    }

    @Test func remoteModelsDispatchesToParakeet() async throws {
        let payload = """
            [{"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z"}]
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models?") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml") == true {
                    let info = """
                        {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z","siblings":[
                          {"rfilename":"model.mlmodelc/x","size":100}
                        ]}
                        """
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(info.utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                ParakeetBackend.overrideRemoteModelsSession = session
                defer { ParakeetBackend.overrideRemoteModelsSession = nil }
                let models = try await Backend.parakeet.remoteModels()
                #expect(models.contains(where: { $0.id == "v3" }) == true)
            }
        )
    }
}
