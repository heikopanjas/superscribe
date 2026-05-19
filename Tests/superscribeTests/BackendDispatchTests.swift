import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Backend dispatch")
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
}
