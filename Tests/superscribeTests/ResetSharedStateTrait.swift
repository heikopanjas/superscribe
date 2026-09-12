import Foundation
import Testing

@testable import SuperscribeKit

/// Gives each test independent dependency storage inherited by its child tasks.
/// Keep the serial runner while the remaining callback boundaries are migrated.
struct ResetSharedStateTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { return true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws -> Void {
        try await SuperscribeKitTestHooks.$testState.withValue(TestDependencyStorage(SuperscribeKitTestHooks.TestState())) {
            try await SuperscribePaths.$testState.withValue(TestDependencyStorage(SuperscribePaths.TestState())) {
                try await CatalogStore.$testState.withValue(TestDependencyStorage(CatalogStore.TestState())) {
                    try await UserConfig.$testState.withValue(TestDependencyStorage(UserConfig.TestState())) {
                        try await WhisperLiveAPI.$testState.withValue(TestDependencyStorage(WhisperLiveAPI.TestState())) {
                            try await AppleSpeechSupport.$testState.withValue(TestDependencyStorage(AppleSpeechSupport.TestState())) {
                                try await ParakeetBackend.$testState.withValue(TestDependencyStorage(ParakeetBackend.TestState())) {
                                    try await WhisperBackend.$testState.withValue(TestDependencyStorage(WhisperBackend.TestState())) {
                                        if #available(macOS 26, *) {
                                            try await AppleSpeechLiveAPI.$testState.withValue(
                                                TestDependencyStorage(AppleSpeechLiveAPI.TestState())
                                            ) {
                                                try await AppleSpeechBackend.$testState.withValue(
                                                    TestDependencyStorage(AppleSpeechBackend.TestState())
                                                ) {
                                                    TestIsolation.resetSharedState()
                                                    try await AppleSpeechLiveAPI.$releaseOperation.withValue(
                                                        { _ in
                                                            Issue.record("Unexpected Apple Speech locale release in a unit test")
                                                        },
                                                        operation: {
                                                            try await TestIsolation.runInTemporaryStorage(function)
                                                        })
                                                }
                                            }
                                        }
                                        else {
                                            TestIsolation.resetSharedState()
                                            try await TestIsolation.runInTemporaryStorage(function)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
