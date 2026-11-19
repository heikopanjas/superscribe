import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("BackendManager", .serialized, ResetSharedStateTrait())
struct BackendManagerTests {
    @Test func cliBackendOverridesConfig() throws -> Void {
        let config = UserConfig(defaultBackend: Backend.whisperCpp.rawValue)
        let backend = try BackendManager.resolveBackend(cliBackend: .parakeet, config: config)
        #expect(backend == .parakeet)
    }

    @Test func configBackendWhenCLINil() throws -> Void {
        let config = UserConfig(defaultBackend: Backend.whisperCpp.rawValue)
        let backend = try BackendManager.resolveBackend(cliBackend: nil, config: config)
        #expect(backend == .whisperCpp)
    }

    @Test func builtInDefaultWhenConfigUnset() throws -> Void {
        let config = UserConfig()
        let backend = try BackendManager.resolveBackend(cliBackend: nil, config: config)
        #expect(backend == .parakeet)
    }

    @Test func explicitModelOverridesConfig() throws -> Void {
        let config = UserConfig(defaultModels: [Backend.parakeet.rawValue: "v2"])
        let (_, model) = try BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: "v3", config: config
        )
        #expect(model == "v3")
    }

    @Test func configModelWhenCLINil() throws -> Void {
        let config = UserConfig(defaultModels: [Backend.parakeet.rawValue: "v2"])
        let (_, model) = try BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: nil, config: config
        )
        #expect(model == "v2")
    }

    @Test func builtInDefaultModelWhenNothingSet() throws -> Void {
        let config = UserConfig()
        let (_, model) = try BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: nil, config: config
        )
        #expect(model == ParakeetBackend.defaultModelId)
    }

    @Test(arguments: [false, true])
    func transcriptionCanonicalizesSelectedModel(explicit: Bool) async throws -> Void {
        let config = UserConfig(defaultModels: [Backend.parakeet.rawValue: "ja"], defaultBackend: Backend.parakeet.rawValue)
        try config.save()
        let cliModel: String? = explicit ? "110m" : nil
        let selection = try BackendManager.resolveBackendAndModel(cliBackend: nil, cliModel: cliModel)
        #expect(selection.backend == .parakeet)
        #expect(selection.model == (explicit ? "110m" : "ja"))
        let (backend, model) = try await PipelineRunner.Dependencies.live.resolveBackendAndModel(nil, cliModel)
        #expect(backend == .parakeet)
        #expect(model == (explicit ? "tdt-ctc-110m" : "tdt-ja"))
    }

    @Test func liveTranscriptionUsesSelectedBackendDefaults() async throws -> Void {
        try UserConfig(defaultModels: [Backend.parakeet.rawValue: "v2"], defaultBackend: Backend.parakeet.rawValue).save()
        let (backend, model) = try await PipelineRunner.Dependencies.live.resolveBackendAndModel(.whisperCpp, nil)
        #expect(backend == .whisperCpp)
        #expect(model == WhisperBackend.defaultModelId)
    }

    @Test func capabilitySelectionDoesNotResolveAppleSpeechAssets() throws -> Void {
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        let config = UserConfig(defaultModels: [Backend.appleSpeech.rawValue: "de_DE"], defaultBackend: Backend.appleSpeech.rawValue)
        let selection = try BackendManager.resolveBackendAndModel(cliBackend: nil, cliModel: nil, config: config)
        #expect(selection.backend == .appleSpeech)
        #expect(selection.model == "de_DE")
    }

    @Test func appleSpeechDefaultFallbackRemainsImplicit() async throws -> Void {
        if #available(macOS 26, *) {
            AppleSpeechSupport.testDefaultLocaleIdentifierOverride = "unsupported"
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["en-US"]
            try UserConfig(defaultBackend: Backend.appleSpeech.rawValue).save()
            let (backend, model) = try await PipelineRunner.Dependencies.live.resolveBackendAndModel(nil, nil)
            #expect(backend == .appleSpeech)
            #expect(model == "en-US")
            await #expect(throws: UnsupportedModelError.self) {
                _ = try await PipelineRunner.Dependencies.live.resolveBackendAndModel(nil, "unsupported")
            }
        }
    }
}
