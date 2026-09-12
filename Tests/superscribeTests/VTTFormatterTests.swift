import Foundation
import Testing

@testable import SuperscribeKit

@Suite("VTTFormatter", .serialized, ResetSharedStateTrait())
struct VTTFormatterTests {
    private func segment(
        speaker: String,
        start: Double,
        end: Double,
        words: [TimedWord] = []
    ) -> MergedSegment {
        return .init(speaker: speaker, start: start, end: end, words: words, paragraphBreak: false)
    }

    @Test("emits WEBVTT header and voice tags")
    func basic() throws -> Void {
        let formatter = VTTFormatter()
        let words = [
            TimedWord(text: "hello", start: 0.0, end: 0.5),
            TimedWord(text: "world", start: 0.5, end: 1.0)
        ]
        let output = try formatter.render([
            self.segment(speaker: "Alice", start: 0.0, end: 1.0, words: words)
        ])
        let expected = """
            WEBVTT

            00:00:00.000 --> 00:00:01.000
            <v Alice>hello world

            """
        #expect(output == expected)
    }

    @Test("includeWords inserts inline word timestamps")
    func wordTimestamps() throws -> Void {
        let formatter = VTTFormatter(includeWords: true)
        let words = [
            TimedWord(text: "hi", start: 0.25, end: 0.5)
        ]
        let output = try formatter.render([
            self.segment(speaker: "Bob", start: 0.0, end: 0.5, words: words)
        ])
        #expect(output.contains("<00:00:00.250>hi"))
        #expect(output.contains("<v Bob>"))
    }

    @Test("timestamp formatting handles hours, minutes, seconds, millis")
    func timestamp() throws -> Void {
        #expect(VTTFormatter.timestamp(0) == "00:00:00.000")
        #expect(VTTFormatter.timestamp(1.234) == "00:00:01.234")
        #expect(VTTFormatter.timestamp(61.5) == "00:01:01.500")
        #expect(VTTFormatter.timestamp(3661.0) == "01:01:01.000")
    }
}
