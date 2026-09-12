import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Owned progress output", .serialized, ResetSharedStateTrait())
struct ProgressReporterTests {
    @Test func finishDrainsOutputAndRejectsLateCallbacks() async -> Void {
        let output = TestDependencyStorage<[String]>([])
        let clock = TestDependencyStorage([0.0, 0.01, 0.2, 0.21])
        let reporter = ProgressReporter(
            now: {
                var times = clock[\.self]
                let time = times.removeFirst()
                clock[\.self] = times
                return time
            },
            write: { output[\.self] += [$0] })
        let source = URL(fileURLWithPath: "/tmp/progress.wav")
        for fraction in [0.1, 0.2, 0.3, 1] {
            reporter.conversion(.init(source: source, framesProcessed: Int64(fraction * 100), framesTotal: 100, fraction: fraction))
        }
        let completion = TranscriptionProgress(speaker: "A", segmentIndex: 3, totalSegments: 3, overallCompleted: 1, overallTotal: 3)
        reporter.transcription(completion)
        await reporter.finish()
        let drained = output[\.self]
        #expect(drained.count == 5)
        #expect(drained[0].contains("10%") == true)
        #expect(drained[1].contains("30%") == true)
        #expect(drained[2].contains("100%") == true)
        #expect(drained[3].contains("overall 1/3") == true)
        #expect(drained[4] == "\r\u{1B}[K")
        reporter.transcription(completion)
        reporter.conversion(.init(source: source, framesProcessed: 100, framesTotal: 100, fraction: 1))
        await reporter.finish()
        #expect(output[\.self] == drained)
    }
}
