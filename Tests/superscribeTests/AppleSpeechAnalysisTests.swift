import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Structured Speech analysis")
struct AppleSpeechAnalysisTests {
    @Test func successCollectsResults() async throws -> Void {
        let spans = [AppleSpeechResultMapping.WordSpan(text: "hello", start: 0, end: 1)]
        let analysis = AppleSpeechAnalysis(
            start: {}, finalize: {}, collect: { return spans },
            cancel: { Issue.record("Successful analysis should not be cancelled") }
        )
        #expect(try await analysis.run() == spans)
    }

    @Test(arguments: ["start", "finalize", "results"])
    func failureCancelsAndJoinsOtherBranch(stage: String) async -> Void {
        let released = TestSignal()
        await confirmation("Framework cancellation", expectedCount: 1) { cancelled in
            let analysis = AppleSpeechAnalysis(
                start: {
                    if stage == "start" { throw CocoaError(.fileReadUnknown) }
                },
                finalize: {
                    if stage == "finalize" { throw CocoaError(.fileReadUnknown) }
                    await released.wait()
                },
                collect: {
                    if stage == "results" { throw CocoaError(.fileReadUnknown) }
                    await released.wait()
                    return []
                },
                cancel: {
                    cancelled()
                    released.signal()
                }
            )
            await #expect(throws: CocoaError.self) { _ = try await analysis.run() }
        }
    }

    @Test func cancellationFinishesUncooperativeBranches() async -> Void {
        let entered = TestSignal()
        let released = TestSignal()
        await confirmation("Framework cancellation", expectedCount: 1) { cancelled in
            let analysis = AppleSpeechAnalysis(
                start: {
                    entered.signal()
                    await released.wait()
                },
                finalize: {},
                collect: {
                    await released.wait()
                    return []
                },
                cancel: {
                    cancelled()
                    released.signal()
                }
            )
            let task = Task { return try await analysis.run() }
            await entered.wait()
            task.cancel()
            await #expect(throws: CancellationError.self) { _ = try await task.value }
        }
    }
}
