import Foundation
import Testing

@testable import SuperscribeKit

@Suite("DownloadProgressTracker")
struct DownloadProgressTrackerTests {

    private final class TickSink: @unchecked Sendable {
        var ticks: [DownloadProgress] = []
    }

    @Test func startAddCompleteFlushUpdatesProgress() async throws {
        let sink = TickSink()
        let tracker = DownloadProgressTracker(
            modelId: "m1",
            backend: .whisperCpp,
            filesTotal: 2,
            bytesTotal: 100,
            onProgress: { sink.ticks.append($0) }
        )

        await tracker.startFile(name: "a.bin")
        await tracker.add(bytes: 40)
        await tracker.completeFile()
        await tracker.startFile(name: "b.bin")
        await tracker.add(bytes: 60)
        await tracker.completeFile()
        await tracker.flush()

        let ticks = sink.ticks
        let last = try #require(ticks.last)
        #expect(last.bytesCompleted == 100)
        #expect(last.filesCompleted == 2)
        #expect(last.filesTotal == 2)
        #expect(last.currentFile == "b.bin")
        #expect(last.modelId == "m1")
        #expect(last.backend == .whisperCpp)
    }

    @Test func rapidAddsAreThrottledUntilFlush() async throws {
        let sink = TickSink()
        let tracker = DownloadProgressTracker(
            modelId: "throttle",
            backend: .parakeet,
            filesTotal: 1,
            bytesTotal: 10_000,
            onProgress: { sink.ticks.append($0) }
        )

        await tracker.startFile(name: "one.bin")
        for _ in 0 ..< 20 {
            await tracker.add(bytes: 10)
        }
        let countAfterBurst = sink.ticks.count
        await tracker.flush()
        #expect(sink.ticks.count >= countAfterBurst + 1)
        let final = try #require(sink.ticks.last)
        #expect(final.bytesCompleted == 200)
    }

    @Test func throughputUsesSlidingWindowAfterOneSecond() async throws {
        let sink = TickSink()
        let tracker = DownloadProgressTracker(
            modelId: "bps",
            backend: .whisperCpp,
            filesTotal: 1,
            bytesTotal: nil,
            onProgress: { sink.ticks.append($0) }
        )

        await tracker.startFile(name: "x.bin")
        await tracker.add(bytes: 50_000)
        try await Task.sleep(for: .milliseconds(1_100))
        await tracker.add(bytes: 50_000)
        await tracker.flush()

        let last = try #require(sink.ticks.last)
        #expect(last.bytesCompleted == 100_000)
        #expect(last.bytesPerSecond != nil)
        if let bps = last.bytesPerSecond {
            #expect(bps > 0)
        }
    }
}
