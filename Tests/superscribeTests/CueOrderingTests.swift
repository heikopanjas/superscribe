import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Chronological split cues", .serialized, ResetSharedStateTrait())
struct CueOrderingTests {
    @Test func splittingAndWordCuesPreserveChronologyAndStableTies() throws -> Void {
        let segments = [
            MergedSegment(speaker: "A", start: 0, end: 6, words: [.init(text: "first", start: 0, end: 1), .init(text: "last", start: 5, end: 6)], paragraphBreak: false),
            MergedSegment(speaker: "B", start: 0, end: 3, words: [.init(text: "tie", start: 0, end: 1), .init(text: "middle", start: 2, end: 3)], paragraphBreak: false)
        ]
        let split = try CueSplitter.split(segments, maximumDuration: 1)
        #expect(split.map(\.start) == [0, 0, 2, 5])
        #expect(split.flatMap(\.words).map(\.text) == ["first", "tie", "middle", "last"])
        let srt = try SRTFormatter(includeWords: true).render(segments)
        let labels = srt.split(separator: "\n").filter { $0.hasPrefix("[") }
        #expect(labels == ["[A] first", "[B] tie", "[B] middle", "[A] last"])
    }
}
