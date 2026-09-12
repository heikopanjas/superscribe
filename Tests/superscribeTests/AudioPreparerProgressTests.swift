import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("AudioPreparer.ConversionProgress", .serialized, ResetSharedStateTrait())
struct AudioPreparerProgressTests {

    @Test func progressFractionsAreMonotonicAndEndAt1() throws -> Void {
        let url = try TestHelpers.makeTempSineWAV(name: "progress", durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: url) }

        let lock = NSLock()
        nonisolated(unsafe) var fractions: [Double] = []
        let preparer = AudioPreparer(targetFormat: .asr16kMono)
        _ = try preparer.loadAndConvert(url: url) { progress in
            lock.lock()
            fractions.append(progress.fraction)
            lock.unlock()
        }

        #expect(!fractions.isEmpty)
        #expect(fractions.last == 1.0)
        // Non-decreasing.
        for (a, b) in zip(fractions, fractions.dropFirst()) {
            #expect(b >= a - 1e-9)
        }
    }
}
