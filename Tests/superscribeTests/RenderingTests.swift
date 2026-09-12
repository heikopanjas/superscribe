import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Complete transcript rendering", .serialized, ResetSharedStateTrait())
struct RenderingTests {
    private func transcript(_ tracks: [(String, [TimedWord])], version: Int = 1) -> IntermediateTranscript {
        return IntermediateTranscript(
            session: nil, created: Date(timeIntervalSince1970: 0),
            tracks: tracks.map { speaker, words in
                .init(speaker: speaker, file: "audio.wav", segments: [.init(start: words.first?.start ?? 0, end: words.map(\.end).max() ?? 0, words: words)])
            }, metadata: .init(backend: .parakeet, model: "test", language: nil, analyzer: .init(silenceThresholdDB: -40, minSilence: 0.5, padding: 0)), version: version)
    }

    @Test func allFormatsHaveDeterministicGoldenOutput() throws -> Void {
        let input = self.transcript([("A&<", [.init(text: "héllo", start: 0, end: 0.5), .init(text: "<world>", start: 0.5, end: 1)])])
        for format in OutputFormat.allCases {
            let file = try #require(Bundle.module.url(forResource: "render", withExtension: format.rawValue, subdirectory: "Fixtures"))
            let golden = try String(contentsOf: file, encoding: .utf8)
            #expect(try TranscriptRenderer.render(input, configuration: .init(format: format)) == golden)
        }
        let json = try TranscriptRenderer.render(input, configuration: .init(format: .json))
        #expect(json == (try TranscriptRenderer.render(input, configuration: .init(format: .json, includeWords: true))))
        let document = try JSONDecoder().decode(MergedTranscriptDocument.self, from: Data(json.utf8))
        #expect(document.version == 1)
        #expect(document.segments[0].text == "héllo <world>")
        #expect(document.segments[0].words == input.tracks[0].segments[0].words)
        #expect(document.segments[0].overlap == false)
        #expect(document.segments[0].paragraphBreak == false)
        #expect(json.range(of: "\"end\"")?.lowerBound ?? json.endIndex < json.range(of: "\"speaker\"")?.lowerBound ?? json.startIndex)
    }

    @Test func threeSpeakersInterleaveWithStableTies() throws -> Void {
        let input = self.transcript([
            ("A", [.init(text: "a", start: 0, end: 3), .init(text: "d", start: 2, end: 4)]),
            ("B", [.init(text: "b", start: 0, end: 1), .init(text: "e", start: 3, end: 5)]),
            ("C", [.init(text: "c", start: 0, end: 1)])
        ])
        let merged = try Merger(config: .init(overlapPolicy: .interleave)).merge(input)
        #expect(merged.map(\.speaker) == ["A", "B", "C", "A", "B"])
        #expect(merged.flatMap(\.words).map(\.text) == ["a", "b", "c", "d", "e"])
        #expect(merged.allSatisfy(\.overlap) == true)
        #expect(try TranscriptRenderer.render(input, configuration: .init(format: .txt)) == "A: a\nB: b\nC: c\nA: d\nB: e\n")
        #expect(throws: InputValidationError.self) { _ = try TranscriptRenderer.render(input, configuration: .init(format: .txt, overlapPolicy: .preserve)) }
        let trimmed = try Merger(config: .init(overlapPolicy: .trim)).merge(input)
        #expect(trimmed.map(\.speaker) == ["C"])
    }

    @Test func trimClampsCrossingWordAndDropsLaterWords() throws -> Void {
        let input = self.transcript([
            ("A", [.init(text: "before", start: 0, end: 2), .init(text: "lost", start: 1, end: 3)]),
            ("B", [.init(text: "interrupt", start: 1, end: 2)])
        ])
        let merged = try Merger(config: .init(overlapPolicy: .trim)).merge(input)
        #expect(merged[0].end == 1)
        #expect(merged[0].words == [.init(text: "before", start: 0, end: 1)])
        #expect(merged[1].words.count == 1)
    }

    @Test func splitPrefersSentenceThenWordAndKeepsIndivisibleSpan() throws -> Void {
        let words: [TimedWord] = [
            .init(text: "One.", start: 0, end: 1), .init(text: "Two", start: 1, end: 2), .init(text: "three", start: 2, end: 3), .init(text: "long", start: 3, end: 8)
        ]
        let input = self.transcript([("A", words)])
        let merged = try Merger(config: .init(maxCueDuration: 2.5)).merge(input)
        #expect(merged.map { $0.words.map(\.text) } == [["One."], ["Two", "three"], ["long"]])
        #expect(merged.flatMap(\.words) == words)
        #expect(merged.last?.end == 8)
    }

    @Test func wrappingCountsCharactersAndTimestampsStayStrictlyInsideCue() throws -> Void {
        let segment = MergedSegment(
            speaker: "A>\nB", start: 0, end: 1,
            words: [
                .init(text: "éé aa", start: 0, end: 0.2), .init(text: "bb", start: 0, end: 0.3), .init(text: "cc", start: 0.5, end: 0.6), .init(text: "ddddddd", start: 0.5, end: 1)
            ], paragraphBreak: false)
        let vtt = try VTTFormatter(includeWords: true, maxLineLength: 5).render([segment])
        #expect(vtt.contains("<v A&gt; B>éé aa\nbb <00:00:00.500>cc\nddddddd") == true)
        #expect(vtt.contains("<00:00:00.000>") == false)
        #expect(vtt.components(separatedBy: "<00:00:00.500>").count == 2)
        let tiny = MergedSegment(speaker: "A", start: 0, end: 0, words: [.init(text: "x", start: 0, end: 0)], paragraphBreak: true)
        #expect(try SRTFormatter(includeWords: true).render([tiny]) == "1\n00:00:00,000 --> 00:00:00,001\n[A] x\n\n")
        #expect(try TXTFormatter(includeWords: true).render([tiny, tiny]) == "A: [00:00:00.000] x\n\nA: [00:00:00.000] x\n")
    }

    @Test func malformedTimingAndVersionsThrow() throws -> Void {
        #expect(throws: InputValidationError.self) { _ = try Merger().merge(self.transcript([], version: 2)) }
        for pair in [(Double.nan, 1.0), (0, Double.infinity), (-1, 1), (2, 1), (0, Double.greatestFiniteMagnitude)] {
            #expect(throws: InputValidationError.self) { _ = try Merger().merge(self.transcript([("A", [.init(text: "x", start: pair.0, end: pair.1)])])) }
        }
        #expect(throws: InputValidationError.self) { _ = try Merger().merge(self.transcript([(" ", [])])) }
        #expect(throws: InputValidationError.self) { _ = try Merger().merge(self.transcript([("A", [.init(text: "x", start: 1, end: 2), .init(text: "y", start: 0, end: 1)])])) }
        for configuration in [RenderConfiguration(maxCueDuration: 0), .init(maxCueDuration: .nan), .init(maxLineLength: 0), .init(gapThreshold: -.infinity)] {
            #expect(throws: InputValidationError.self) { try configuration.validate() }
        }
        #expect(try TranscriptRenderer.render(self.transcript([])) == "WEBVTT\n")
        #expect(try TranscriptRenderer.render(self.transcript([]), configuration: .init(format: .txt)).isEmpty == true)
    }

    @Test func cliAndLibraryShareRendering() throws -> Void {
        let input = self.transcript([("A", [.init(text: "hello", start: 0, end: 1)])])
        for format in OutputFormat.allCases {
            var options = try MergeOptions.parse([])
            options.format = format
            options.includeWords = true
            #expect(try MergeCommand.renderMerged(input, options: options) == TranscriptRenderer.render(input, configuration: options.renderConfiguration))
        }
    }
}
