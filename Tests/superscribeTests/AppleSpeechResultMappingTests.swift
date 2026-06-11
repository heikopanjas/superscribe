import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech result mapping", .serialized, ResetSharedStateTrait())
struct AppleSpeechResultMappingTests {
    @Test func mapOffsetsWordsBySegmentStart() {
        let spans = [
            AppleSpeechResultMapping.WordSpan(text: "hello", start: 0.1, end: 0.4),
            AppleSpeechResultMapping.WordSpan(text: "world", start: 0.5, end: 0.9),
        ]
        let words = AppleSpeechResultMapping.map(spans: spans, segmentOffset: 12.0)
        #expect(words.count == 2)
        #expect(words[0].text == "hello")
        #expect(words[0].start == 12.1)
        #expect(words[1].end == 12.9)
    }

    @Test func mapDropsWhitespaceOnlySpans() {
        let spans = [AppleSpeechResultMapping.WordSpan(text: "   ", start: 0.0, end: 0.2)]
        #expect(AppleSpeechResultMapping.map(spans: spans, segmentOffset: 0).isEmpty == true)
    }
}
