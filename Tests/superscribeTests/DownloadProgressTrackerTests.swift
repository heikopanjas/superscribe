import Foundation
import Testing

@testable import SuperscribeKit

@Suite("DownloadProgressTracker", .serialized, ResetSharedStateTrait())
struct DownloadProgressTrackerTests {
    @Test func zeroBytesAndElapsedTimeHaveNoRate() async throws -> Void {
        let clock = TestDependencyStorage(0.0)
        let ticks = TestDependencyStorage<[DownloadProgress]>([])
        let tracker = DownloadProgressTracker(
            modelId: "empty", backend: .parakeet, filesTotal: 1, bytesTotal: nil,
            onProgress: {
                ticks[\.self].append($0)
            }, now: { return clock[\.self] })
        await tracker.flush()
        clock[\.self] = 0.5
        await tracker.flush()
        #expect(ticks[\.self].allSatisfy { $0.bytesPerSecond == nil } == true)
        await tracker.add(bytes: 10)
        await tracker.flush()
        #expect(ticks[\.self].last?.bytesPerSecond == 20)
    }

    private final class TickSink: Sendable {
        private let storage = TestDependencyStorage<[DownloadProgress]>([])
        var ticks: [DownloadProgress] {
            get { return self.storage[\.self] }
            set { self.storage[\.self] = newValue }
        }
    }

    @Test func startAddCompleteFlushUpdatesProgress() async throws -> Void {
        let sink = TickSink()
        let clock = TestDependencyStorage(0.0)
        let tracker = DownloadProgressTracker(
            modelId: "m1",
            backend: .whisperCpp,
            filesTotal: 2,
            bytesTotal: 100,
            onProgress: { sink.ticks.append($0) },
            now: { return clock[\.self] }
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

    @Test func rapidAddsAreThrottledUntilFlush() async throws -> Void {
        let sink = TickSink()
        let clock = TestDependencyStorage(0.0)
        let tracker = DownloadProgressTracker(
            modelId: "throttle",
            backend: .parakeet,
            filesTotal: 1,
            bytesTotal: 10_000,
            onProgress: { sink.ticks.append($0) },
            now: { return clock[\.self] }
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

    @Test func zeroByteWindowSkipsThroughputUpdate() async throws -> Void {
        let sink = TickSink()
        let clock = TestDependencyStorage(0.0)
        let tracker = DownloadProgressTracker(
            modelId: "zero-delta",
            backend: .parakeet,
            filesTotal: 1,
            bytesTotal: 100,
            onProgress: { sink.ticks.append($0) },
            now: { return clock[\.self] }
        )

        await tracker.startFile(name: "x.bin")
        await tracker.add(bytes: 100)
        clock[\.self] += 1.1
        await tracker.flush()
        clock[\.self] += 1.1
        await tracker.flush()

        #expect(sink.ticks.count >= 2)
    }

    @Test func throughputUsesSlidingWindowAfterOneSecond() async throws -> Void {
        let sink = TickSink()
        let clock = TestDependencyStorage(0.0)
        let tracker = DownloadProgressTracker(
            modelId: "bps",
            backend: .whisperCpp,
            filesTotal: 1,
            bytesTotal: nil,
            onProgress: { sink.ticks.append($0) },
            now: { return clock[\.self] }
        )

        await tracker.startFile(name: "x.bin")
        await tracker.add(bytes: 50_000)
        clock[\.self] += 1.1
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
