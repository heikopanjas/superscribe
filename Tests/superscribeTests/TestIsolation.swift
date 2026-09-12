import Foundation
import Testing

@testable import SuperscribeKit

enum TestIsolation {
    static func runInTemporaryStorage(_ function: @Sendable () async throws -> Void) async throws -> Void {
        try await TestHelpers.withTempDirectory(prefix: "test-scope") { root in
            SuperscribePaths.overrideFluidAudioModelsDirectory = root.appendingPathComponent("parakeet")
            SuperscribePaths.overrideWhisperModelCacheDirectory = root.appendingPathComponent("whisper")
            CatalogStore.overrideURL = root.appendingPathComponent("catalog.json")
            UserConfig.overrideConfigFileURL = root.appendingPathComponent("config.json")
            try await function()
        }
    }

    static func resetSharedState() -> Void {
        SuperscribeKitTestHooks.resetAll()
        SuperscribePaths.overrideFluidAudioModelsDirectory = nil
        SuperscribePaths.overrideWhisperModelCacheDirectory = nil
        CatalogStore.overrideURL = nil
        UserConfig.overrideConfigFileURL = nil
        WhisperBackend.overrideRemoteModelsSession = nil
        WhisperBackend.defaultRemoteModelsSession = .shared
        ParakeetBackend.overrideRemoteModelsSession = nil
        ParakeetBackend.defaultRemoteModelsSession = .shared
        ParakeetBackend.testLoadHook = nil
        ParakeetBackend.testForceUnavailable = false
        WhisperBackend.testForceUnavailable = false
        WhisperBackend.testForceStateInitFailed = false
        WhisperBackend.testForceTranscriptionFailed = false
        WhisperBackend.testForceNilTokenText = false
        WhisperBackend.testNilTokenTextSkipsRemaining = 0
        WhisperBackend.testUseStubLoad = false
        WhisperBackend.testWhisperAPISegments = nil
        WhisperBackend.testWhisperInitPointer = nil
        WhisperBackend.testWhisperStatePointer = nil
        WhisperLiveAPI.testSkipContextRelease = false
        AppleSpeechSupport.testForceRuntimeUnavailable = false
        AppleSpeechSupport.testOSMajorVersionOverride = nil
        AppleSpeechSupport.testForceAPIAvailabilityFalse = false
        AppleSpeechSupport.testDefaultLocaleIdentifierOverride = nil
        if #available(macOS 26, *) {
            AppleSpeechBackend.testForceUnavailable = false
            AppleSpeechBackend.testLoadHook = nil
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["en-US"]
            AppleSpeechLiveAPI.testInstalledLocaleIds = []
            AppleSpeechLiveAPI.testReservedLocaleIds = []
            AppleSpeechLiveAPI.testTranscriptionSpans = []
            AppleSpeechLiveAPI.testForceInstallFailure = false
            AppleSpeechLiveAPI.testForceTranscriptionFailure = false
            AppleSpeechLiveAPI.testSkipLiveTranscription = false
            AppleSpeechLiveAPI.testForceReserveFailure = false
            AppleSpeechLiveAPI.testForceUnsupportedLocale = false
            AppleSpeechLiveAPI.testSkipLocaleInstall = false
        }
    }
}
