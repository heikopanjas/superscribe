import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Model lifecycle regressions", .serialized, ResetSharedStateTrait())
struct ModelLifecycleRegressionTests {
    @Test func removingVariantRetainsSharedEncoder() async throws -> Void {
        let first = WhisperBackend.installPath(for: "tiny-q5_0")
        let second = WhisperBackend.installPath(for: "tiny-q8_0")
        let encoder = WhisperBackend.encoderInstallPath(for: "tiny")
        try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
        try Data("ggml".utf8).write(to: first)
        try Data("ggml".utf8).write(to: second)
        #expect(try await ModelInstaller.removalPaths(modelId: "tiny-q5_0", backend: .whisperCpp) == [first])
        try await ModelInstaller.removeInstalled(modelId: "tiny-q5_0", backend: .whisperCpp)
        #expect(FileManager.default.fileExists(atPath: encoder.path) == true)
        try await ModelInstaller.removeInstalled(modelId: "tiny-q8_0", backend: .whisperCpp)
        #expect(FileManager.default.fileExists(atPath: encoder.path) == false)
    }

    @Test func incompleteAndStagingDirectoriesAreNotAdvertised() throws -> Void {
        let binDirectory = WhisperBackend.installPath(for: "tiny")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        #expect(try WhisperBackend.installedModels().isEmpty == true)
        let staging = SuperscribePaths.fluidAudioModelsDirectory().appendingPathComponent("parakeet-tdt-0.6b-v3.staging-test/model.mlmodelc")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        #expect(try ParakeetBackend.installedModels().isEmpty == true)
    }

    @Test func appleReservationAndInstallationAreIndependent() async throws -> Void {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["en-US", "de-DE"]
            AppleSpeechLiveAPI.testReservedLocaleIds = ["de-DE", "fr-FR"]
            let models = try await AppleSpeechBackend.installedModels()
            #expect(models.map(\.state) == [.installedAndReserved, .installed, .reserved])
            #expect(models.map { $0.state.hasInstalledAssets } == [true, true, false])
            let released = TestDependencyStorage<[String]>([])
            await AppleSpeechLiveAPI.$releaseOperation.withValue(
                { locale in released[\.self] = [AppleSpeechSupport.normalizeLocaleId(locale.identifier)] },
                operation: {
                    await AppleSpeechAssetInstaller.release(localeId: "fr-FR")
                })
            #expect(released[\.self] == ["fr-FR"])
        }
    }

    @Test func supportedDefaultFallbackAndAliases() async throws -> Void {
        #expect(try await Backend.parakeet.resolveModelId("110m") == "tdt-ctc-110m")
        #expect(try await Backend.parakeet.resolveModelId() == "v3")
        #expect(try await Backend.whisperCpp.resolveModelId() == WhisperBackend.defaultModelId)
        #expect(try await Backend.whisperCpp.resolveModelId("tiny") == "tiny")
        if #available(macOS 26, *) {
            AppleSpeechSupport.testDefaultLocaleIdentifierOverride = "unsupported"
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["en-US", "de-DE"]
            #expect(try await Backend.appleSpeech.resolveModelId() == "en-US")
            #expect(try await Backend.appleSpeech.resolveModelId("de_DE") == "de-DE")
            await #expect(throws: UnsupportedModelError.self) { _ = try await Backend.appleSpeech.resolveModelId("unsupported") }
            AppleSpeechLiveAPI.testSupportedLocaleIds = []
            await #expect(throws: UnsupportedModelError.self) { _ = try await Backend.appleSpeech.resolveModelId() }
            AppleSpeechSupport.testForceRuntimeUnavailable = true
            await #expect(throws: BackendTranscriberError.self) { _ = try await Backend.appleSpeech.resolveModelId() }
        }
    }
}
