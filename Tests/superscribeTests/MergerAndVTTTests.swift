import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Merger")
struct MergerTests {
    private func track(
        _ speaker: String, _ segments: [(Double, Double)]
    )
        -> IntermediateTranscript
        .Track
    {
        .init(
            speaker: speaker,
            file: "\(speaker).wav",
            segments: segments.map { .init(start: $0.0, end: $0.1, words: []) }
        )
    }

    private func transcript(_ tracks: [IntermediateTranscript.Track]) -> IntermediateTranscript {
        .init(
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
    func chronological() {
        let merger = Merger()
        let result = merger.merge(
            transcript([
                track("Alice", [(0.0, 1.0)]),
                track("Bob", [(2.0, 3.0)])
            ]))
        #expect(result.map(\.speaker) == ["Alice", "Bob"])
    }

    @Test("adjacent same-speaker segments under maxCoalesceGap are coalesced")
    func coalesce() throws {
        let merger = Merger(config: .init(gapThreshold: 5.0, maxCoalesceGap: 1.0))
        let result = merger.merge(
            transcript([
                track("Alice", [(0.0, 1.0), (1.5, 2.5)])
            ]))
        let only = try #require(result.first)
        #expect(result.count == 1)
        #expect(only.start == 0.0)
        #expect(only.end == 2.5)
    }

    @Test("gap >= gapThreshold is not coalesced and marks paragraph break")
    func paragraphBreak() {
        let merger = Merger(config: .init(gapThreshold: 2.0, maxCoalesceGap: 5.0))
        let result = merger.merge(
            transcript([
                track("Alice", [(0.0, 1.0), (3.5, 4.5)])
            ]))
        #expect(result.count == 2)
        #expect(result[1].paragraphBreak == true)
    }
}

@Suite("VTTFormatter")
struct VTTFormatterTests {
    private func segment(
        speaker: String,
        start: Double,
        end: Double,
        words: [TimedWord] = []
    ) -> MergedSegment {
        .init(speaker: speaker, start: start, end: end, words: words, paragraphBreak: false)
    }

    @Test("emits WEBVTT header and voice tags")
    func basic() {
        let formatter = VTTFormatter()
        let words = [
            TimedWord(text: "hello", start: 0.0, end: 0.5),
            TimedWord(text: "world", start: 0.5, end: 1.0)
        ]
        let output = formatter.render([
            segment(speaker: "Alice", start: 0.0, end: 1.0, words: words)
        ])
        let expected = """
            WEBVTT

            00:00:00.000 --> 00:00:01.000
            <v Alice>hello world

            """
        #expect(output == expected)
    }

    @Test("includeWords inserts inline word timestamps")
    func wordTimestamps() {
        let formatter = VTTFormatter(includeWords: true)
        let words = [
            TimedWord(text: "hi", start: 0.25, end: 0.5)
        ]
        let output = formatter.render([
            segment(speaker: "Bob", start: 0.0, end: 0.5, words: words)
        ])
        #expect(output.contains("<00:00:00.250>hi"))
        #expect(output.contains("<v Bob>"))
    }

    @Test("timestamp formatting handles hours, minutes, seconds, millis")
    func timestamp() {
        #expect(VTTFormatter.timestamp(0) == "00:00:00.000")
        #expect(VTTFormatter.timestamp(1.234) == "00:00:01.234")
        #expect(VTTFormatter.timestamp(61.5) == "00:01:01.500")
        #expect(VTTFormatter.timestamp(3661.0) == "01:01:01.000")
    }
}
