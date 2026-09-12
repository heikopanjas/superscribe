import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Interleaving pauses", .serialized, ResetSharedStateTrait())
struct InterleavingPauseTests {
    @Test func sameSpeakerPauseStartsAParagraphAndTrimKeepsUncontestedWords() throws -> Void {
        let input = IntermediateTranscript(
            session: nil,
            tracks: [.init(speaker: "A", file: "", segments: [.init(start: 0, end: 10, words: [.init(text: "first", start: 0, end: 1), .init(text: "last", start: 9, end: 10)])])],
            metadata: .init(backend: .parakeet, model: "m", language: nil, analyzer: .init(silenceThresholdDB: -40, minSilence: 0.5, padding: 0)))
        #expect(try TranscriptRenderer.render(input, configuration: .init(format: .txt)) == "A: first\n\nA: last\n")
        #expect(try Merger(config: .init(overlapPolicy: .trim)).merge(input).flatMap(\.words).count == 2)
    }
}
