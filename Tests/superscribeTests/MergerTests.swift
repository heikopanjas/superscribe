import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Merger", .serialized, ResetSharedStateTrait())
struct MergerTests {
    private func track(
        _ speaker: String, _ segments: [(Double, Double)]
    )
        -> IntermediateTranscript
        .Track
    {
        return .init(
            speaker: speaker,
            file: "\(speaker).wav",
            segments: segments.map { .init(start: $0.0, end: $0.1, words: [.init(text: "word", start: $0.0, end: $0.1)]) }
        )
    }

    private func transcript(_ tracks: [IntermediateTranscript.Track]) -> IntermediateTranscript {
        return .init(
            session: nil,
            tracks: tracks,
            metadata: .init(
                backend: .parakeet,
                model: "test",
                language: nil,
                analyzer: .init(silenceThresholdDB: -40, minSilence: 0.5, padding: 0.15)
            )
        )
    }

    @Test("two non-overlapping speakers ordered chronologically")
    func chronological() throws -> Void {
        let merger = Merger()
        let result = try merger.merge(
            self.transcript([
                self.track("Alice", [(0.0, 1.0)]),
                self.track("Bob", [(2.0, 3.0)])
            ]))
        #expect(result.map(\.speaker) == ["Alice", "Bob"])
    }

    @Test("adjacent same-speaker segments under maxCoalesceGap are coalesced")
    func coalesce() throws -> Void {
        let merger = Merger(config: .init(gapThreshold: 5.0, maxCoalesceGap: 1.0))
        let result = try merger.merge(
            self.transcript([
                self.track("Alice", [(0.0, 1.0), (1.5, 2.5)])
            ]))
        let only = try #require(result.first)
        #expect(result.count == 1)
        #expect(only.start == 0.0)
        #expect(only.end == 2.5)
    }

    @Test("gap >= gapThreshold is not coalesced and marks paragraph break")
    func paragraphBreak() throws -> Void {
        let merger = Merger(config: .init(gapThreshold: 2.0, maxCoalesceGap: 5.0))
        let result = try merger.merge(
            self.transcript([
                self.track("Alice", [(0.0, 1.0), (3.5, 4.5)])
            ]))
        #expect(result.count == 2)
        #expect(result[1].paragraphBreak == true)
    }
}
