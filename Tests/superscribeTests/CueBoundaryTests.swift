import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Nested cues and timing bounds", .serialized, ResetSharedStateTrait())
struct CueBoundaryTests {
    @Test func nestedSegmentsKeepContainingEndAndStableWords() throws -> Void {
        let segments = [
            MergedSegment(speaker: "A", start: 0, end: 10, words: [.init(text: "first", start: 0, end: 5), .init(text: "later", start: 4, end: 10)], paragraphBreak: false),
            MergedSegment(speaker: "A", start: 1, end: 2, words: [.init(text: "inside", start: 1, end: 2), .init(text: "tie", start: 1, end: 2)], paragraphBreak: false)
        ]
        let merged = Merger.coalesce(segments, maxCueDuration: nil, maxGap: 1)
        #expect(merged.count == 1)
        #expect(merged[0].end == 10)
        #expect(merged[0].words.map(\.text) == ["first", "inside", "tie", "later"])
        let attributed = segments.map { AttributedSegment(speaker: $0.speaker, start: $0.start, end: $0.end, words: $0.words) }
        #expect(Merger.insertBreaks(attributed, gapThreshold: 3).allSatisfy { $0.overlap == false } == true)
        #expect(try Merger.flatten([.init(speaker: "A", file: "", segments: [.init(start: 0, end: 1, words: [])])]).isEmpty == true)
    }

    @Test func splittingRetainsFinalCueBoundsAndAllowsEmptyTimedSpans() throws -> Void {
        let segment = MergedSegment(speaker: "A", start: 0, end: 3, words: [.init(text: " ", start: 0, end: 1), .init(text: "second", start: 2, end: 2.5)], paragraphBreak: true)
        let cues = try CueSplitter.split([segment], maximumDuration: 2)
        #expect(cues.last?.end == 3)
        #expect(throws: InputValidationError.self) { _ = try CueSplitter.split([], maximumDuration: 0) }
        let extended = try VTTFormatter(includeWords: true).render([MergedSegment(speaker: "A", start: 1, end: 2, words: [.init(text: "early", start: 0, end: 3)], paragraphBreak: false)])
        #expect(extended.contains("00:00:00.000 --> 00:00:03.000") == true)
    }
}
