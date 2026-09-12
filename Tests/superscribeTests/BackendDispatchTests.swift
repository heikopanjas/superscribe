import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Backend dispatch", .serialized, ResetSharedStateTrait())
struct BackendDispatchTests {
    @Test func registryDefaultModelIds() -> Void {
        #expect(Backend.parakeet.registryDefaultModelId == ParakeetBackend.defaultModelId)
        #expect(Backend.whisperCpp.registryDefaultModelId == WhisperBackend.defaultModelId)
        #expect(Backend.appleSpeech.registryDefaultModelId == AppleSpeechSupport.defaultLocaleId)
    }

    @Test func installPathForWhisper() throws -> Void {
        let path = try Backend.whisperCpp.installPath(for: "base")
        #expect(path.lastPathComponent == "base.bin")
        #expect(path.path.contains("whisper"))
    }

    @Test func installPathForParakeet() throws -> Void {
        let path = try Backend.parakeet.installPath(for: "v3")
        #expect(path.lastPathComponent.contains("v3") || path.path.contains("v3"))
    }

    @Test func installPathForAppleSpeechWhenUnavailable() -> Void {
        if AppleSpeechSupport.isRuntimeAvailable() == false {
            #expect(throws: ModelInstallationError.self) {
                _ = try Backend.appleSpeech.installPath(for: "en-US")
            }
        }
    }

    @Test func installedModelsEmptyForAppleSpeechWhenUnavailable() async throws -> Void {
        if AppleSpeechSupport.isRuntimeAvailable() == false {
            #expect(try await Backend.appleSpeech.installedModels().isEmpty == true)
        }
    }

    @Test func installedModelsDispatchesToAppleSpeechWhenAvailable() async throws -> Void {
        if #available(macOS 26, *) {
            if AppleSpeechSupport.isRuntimeAvailable() == true {
                AppleSpeechLiveAPI.testInstalledLocaleIds = ["en-US"]
                defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }
                let models = try await Backend.appleSpeech.installedModels()
                #expect(models.contains(where: { $0.id == "en-US" }) == true)
            }
        }
    }

    @Test func makeTranscriberReturnsParakeetOnArm64() throws -> Void {
        #if arch(arm64)
        let t = try Backend.parakeet.makeTranscriber(model: "v3")
        #expect(t.capabilities.defaultModelId == ParakeetBackend.defaultModelId)
        #else
        #expect(Bool(false), "Unexpected non-arm64 host")
        #endif
    }

    @Test func makeTranscriberAppleSpeechUnavailableWhenForced() -> Void {
        let prior = AppleSpeechSupport.testForceRuntimeUnavailable
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        defer { AppleSpeechSupport.testForceRuntimeUnavailable = prior }
        #expect(throws: BackendTranscriberError.self) {
            _ = try Backend.appleSpeech.makeTranscriber(model: "en-US")
        }
    }

    @Test func makeTranscriberAppleSpeechUnavailableBelowMacOS26() -> Void {
        let priorVersion = AppleSpeechSupport.testOSMajorVersionOverride
        AppleSpeechSupport.testOSMajorVersionOverride = 25
        defer { AppleSpeechSupport.testOSMajorVersionOverride = priorVersion }
        #expect(throws: BackendTranscriberError.self) {
            _ = try Backend.appleSpeech.makeTranscriber(model: "en-US")
        }
    }

    @Test func makeTranscriberAppleSpeechUnavailableWhenAPIForcedOff() -> Void {
        let prior = AppleSpeechSupport.testForceAPIAvailabilityFalse
        AppleSpeechSupport.testForceAPIAvailabilityFalse = true
        defer { AppleSpeechSupport.testForceAPIAvailabilityFalse = prior }
        #expect(throws: BackendTranscriberError.self) {
            _ = try Backend.appleSpeech.makeTranscriber(model: "en-US")
        }
    }

    @Test func makeTranscriberReturnsAppleSpeechOnMacOS26() throws -> Void {
        if #available(macOS 26, *) {
            let t = try Backend.appleSpeech.makeTranscriber(model: "en-US")
            #expect(t.capabilities.displayName == "Apple Speech")
        }
    }

    @Test func makeTranscriberParakeetUnavailableWhenForced() -> Void {
        let prior = ParakeetBackend.testForceUnavailable
        ParakeetBackend.testForceUnavailable = true
        defer { ParakeetBackend.testForceUnavailable = prior }
        #expect(throws: BackendTranscriberError.self) {
            _ = try Backend.parakeet.makeTranscriber(model: "v3")
        }
    }

    @Test func makeTranscriberWhisperUnavailableWhenForced() -> Void {
        let prior = WhisperBackend.testForceUnavailable
        WhisperBackend.testForceUnavailable = true
        defer { WhisperBackend.testForceUnavailable = prior }
        #expect(throws: BackendTranscriberError.self) {
            _ = try Backend.whisperCpp.makeTranscriber(model: "tiny")
        }
    }

    @Test func remoteModelsDispatchesToWhisper() async throws -> Void {
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
                WhisperBackend.overrideRemoteModelsSession = session
                defer { WhisperBackend.overrideRemoteModelsSession = nil }
                let models = try await Backend.whisperCpp.remoteModels()
                #expect(models.contains(where: { $0.id == "tiny" }) == true)
            }
        )
    }

    @Test func remoteModelsDispatchesToParakeet() async throws -> Void {
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
                ParakeetBackend.overrideRemoteModelsSession = session
                defer { ParakeetBackend.overrideRemoteModelsSession = nil }
                let models = try await Backend.parakeet.remoteModels()
                #expect(models.contains(where: { $0.id == "v3" }) == true)
            }
        )
    }
}
