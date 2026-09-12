import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Pipeline limits", .serialized, ResetSharedStateTrait())
struct PipelineLimitTests {
    @Test(arguments: [(0, 1), (1, 0)])
    func validatesLimitsBeforePreparingAudio(limits: (Int, Int)) async throws -> Void {
        let source = try TestHelpers.makeTempSineWAV(name: "limits")
        defer { try? FileManager.default.removeItem(at: source) }
        let pipeline = TranscribePipeline(
            transcriber: MockTranscriber(),
            config: .init(tracks: [.init(speaker: "A", file: source)], transcriptionConfig: .init(), maxConcurrentTranscriptions: limits.0, maxConcurrentConversions: limits.1))
        await #expect(throws: BoundedTaskGroupError.self) { _ = try await pipeline.run() }
    }
}
