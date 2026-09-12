import Testing

@testable import SuperscribeKit

@Suite("Dependency isolation")
struct DependencyIsolationTests {
    @Test func overlappingScopesKeepIndependentOverrides() async -> Void {
        let gate = ConcurrentTestGate(batchSize: 2)
        await withTaskGroup(of: Void.self) { group in
            for unavailable in [false, true] {
                group.addTask {
                    await AppleSpeechSupport.$testState.withValue(TestDependencyStorage(AppleSpeechSupport.TestState())) {
                        AppleSpeechSupport.testForceRuntimeUnavailable = unavailable
                        AppleSpeechSupport.testOSMajorVersionOverride = 26
                        await gate.enter()
                        #expect(AppleSpeechSupport.isRuntimeAvailable() == (unavailable == false))
                        await gate.leave()
                    }
                }
            }
        }
        #expect(await gate.current == 0)
    }
}
