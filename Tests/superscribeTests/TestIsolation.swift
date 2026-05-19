import Foundation
import Testing

@testable import SuperscribeKit

/// Resets process-wide test doubles before and after every test.
///
/// Swift Testing runs tests in parallel by default (even when SPM's `--no-parallel`
/// is the default). Shared hooks and path overrides require serial execution —
/// use `swift test --no-parallel` or `_scripts/test.sh`.
struct ResetSharedStateTrait: SuiteTrait, TestTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        TestIsolation.resetSharedState()
        defer { TestIsolation.resetSharedState() }
        try await function()
    }
}

enum TestIsolation {
    static func resetSharedState() {
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
    }
}
