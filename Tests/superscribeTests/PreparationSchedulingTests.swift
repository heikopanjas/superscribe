import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Bounded preparation", .serialized, ResetSharedStateTrait())
struct PreparationSchedulingTests {
    @Test(arguments: [false, true])
    func conversionLimitAndTemporaryCleanup(cancel: Bool) async throws -> Void {
        let sources = try (0 ..< 3).map { try TestHelpers.makeTempSineWAV(name: "prepare-\($0)", durationSeconds: 2) }
        defer { for source in sources { try? FileManager.default.removeItem(at: source) } }
        let gate = BlockingTestGate()
        let lock = NSLock()
        nonisolated(unsafe) var preparedFiles = Set<URL>()
        let dependencies = AudioBuffers.Dependencies(
            read: { file, buffer, count in
                if file.url.lastPathComponent.hasPrefix("superscribe-") == true {
                    _ = lock.withLock { preparedFiles.insert(file.url) }
                }
                try file.read(into: buffer, frameCount: count)
            },
            allocate: { format, frames in
                // Streaming conversion uses 16K-frame buffers; active segments alone may use 32K.
                #expect(frames <= 32_000)
                return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
            })
        let pipeline = TranscribePipeline(
            transcriber: MockTranscriber(),
            config: .init(tracks: sources.enumerated().map { .init(speaker: "\($0.offset)", file: $0.element) }, transcriptionConfig: .init()),
            onConversionProgress: { progress in
                if progress.fraction == 1 { gate.enter() }
            })
        let task = Task {
            return try await AudioBuffers.$dependencies.withValue(dependencies) { try await pipeline.run() }
        }
        await gate.initialBatch.wait()
        #expect(gate.current == 2)
        gate.release()
        await gate.nextArrival.wait()
        if cancel == true { task.cancel() }
        gate.release()
        gate.release()
        if cancel == true {
            await #expect(throws: CancellationError.self) { _ = try await task.value }
        }
        else {
            #expect(try await task.value.tracks.count == 3)
        }
        #expect(gate.peak == 2)
        #expect(gate.current == 0)
        #expect(preparedFiles.isEmpty == false)
        #expect(preparedFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) == false } == true)
    }
}
