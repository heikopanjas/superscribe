import Foundation
import Testing

@testable import SuperscribeKit

@Suite("TokenAccumulator", .serialized, ResetSharedStateTrait())
struct TokenMergingTests {
    @Test func mergesSentencePieceBoundaries() {
        var acc = TokenAccumulator()
        acc.accept(token: "▁hello", start: 0.0, end: 0.5)
        acc.accept(token: "▁world", start: 0.5, end: 1.0)
        let words = acc.finish(segmentOffset: 10.0)
        #expect(words.count == 2)
        #expect(words[0].text == "hello")
        #expect(words[0].start == 10.0)
        #expect(words[0].end == 10.5)
        #expect(words[1].text == "world")
        #expect(words[1].start == 10.5)
        #expect(words[1].end == 11.0)
    }

    @Test func mergesLeadingSpaceBoundaries() {
        var acc = TokenAccumulator()
        acc.accept(token: " foo", start: 1.0, end: 1.2)
        acc.accept(token: " bar", start: 1.2, end: 1.4)
        let words = acc.finish(segmentOffset: 0)
        #expect(words.map(\.text) == ["foo", "bar"])
    }

    @Test func skipsEmptyTokens() {
        var acc = TokenAccumulator()
        acc.accept(token: "   ", start: 0, end: 0.1)
        acc.accept(token: "▁ok", start: 0.1, end: 0.2)
        let words = acc.finish(segmentOffset: 0)
        #expect(words.count == 1)
        #expect(words[0].text == "ok")
    }

    @Test func flushesFinalWord() {
        var acc = TokenAccumulator()
        acc.accept(token: "▁only", start: 2.0, end: 3.0)
        let words = acc.finish(segmentOffset: 5.0)
        #expect(words.count == 1)
        #expect(words[0].text == "only")
        #expect(words[0].start == 7.0)
        #expect(words[0].end == 8.0)
    }

    @Test func concatenatesSubwordPieces() {
        var acc = TokenAccumulator()
        acc.accept(token: "▁trans", start: 0.0, end: 0.3)
        acc.accept(token: "cript", start: 0.3, end: 0.6)
        let words = acc.finish(segmentOffset: 0)
        #expect(words.count == 1)
        #expect(words[0].text == "transcript")
    }

    @Test func finishWithNoTokensReturnsEmpty() {
        let acc = TokenAccumulator()
        let words = acc.finish(segmentOffset: 0)
        #expect(words.isEmpty == true)
    }
}
