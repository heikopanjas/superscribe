import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Merger / FS / Catalog / LoadOnce / HuggingFace

@Suite("Merger overlap policies", .serialized, ResetSharedStateTrait())
struct MergerOverlapTests {
    @Test func coalesceRespectsMaxCueDuration() throws -> Void {
        let merger = Merger(config: .init(gapThreshold: 10, maxCueDuration: 1.0, maxCoalesceGap: 2.0))
        let transcript = IntermediateTranscript(
            session: nil,
            tracks: [
                .init(
                    speaker: "A",
                    file: "a.wav",
                    segments: [
                        .init(start: 0, end: 0.8, words: [TimedWord(text: "a", start: 0, end: 0.8)]),
                        .init(start: 1.0, end: 2.5, words: [TimedWord(text: "b", start: 1, end: 2.5)])
                    ]
                )
            ],
            metadata: .init(
                backend: .parakeet,
                model: "m",
                language: nil,
                analyzer: .init(silenceThresholdDB: -40, minSilence: 0.5, padding: 0.15)
            )
        )
        let merged = try merger.merge(transcript)
        #expect(merged.count == 2)
    }
}
