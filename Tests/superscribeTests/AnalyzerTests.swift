import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Analyzer")
struct AnalyzerTests {
    private let sampleRate: Double = 48_000

    /// Generate a sine-wave tone at full amplitude.
    private func tone(seconds: Double, amplitude: Float = 0.5) -> [Float] {
        let count = Int(seconds * sampleRate)
        let twoPiOverRate = 2.0 * .pi * 440.0 / sampleRate
        return (0 ..< count).map { amplitude * Float(sin(twoPiOverRate * Double($0))) }
    }

    private func silence(seconds: Double) -> [Float] {
        Array(repeating: 0, count: Int(seconds * sampleRate))
    }

    @Test("pure silence yields no segments")
    func pureSilence() {
        let analyzer = Analyzer()
        let segments = analyzer.detectSpeech(samples: silence(seconds: 2), sampleRate: sampleRate)
        #expect(segments.isEmpty)
    }

    @Test("constant tone yields one segment spanning the file")
    func constantTone() {
        let analyzer = Analyzer()
        let samples = tone(seconds: 2)
        let segments = analyzer.detectSpeech(samples: samples, sampleRate: sampleRate)
        let segment = try! #require(segments.first)
        #expect(segments.count == 1)
        // With padding the segment may extend slightly beyond [0, 2] but is
        // clamped to file duration.
        #expect(segment.start == 0)
        #expect(segment.end == 2)
    }

    @Test("tone-silence-tone yields two segments with correct boundaries")
    func toneSilenceTone() {
        let analyzer = Analyzer(config: AnalyzerConfig(padding: 0))
        let samples = tone(seconds: 1) + silence(seconds: 1) + tone(seconds: 1)
        let segments = analyzer.detectSpeech(samples: samples, sampleRate: sampleRate)
        #expect(segments.count == 2)
        let first = try! #require(segments.first)
        let second = try! #require(segments.last)
        #expect(abs(first.start - 0) < 0.05)
        #expect(abs(first.end - 1) < 0.05)
        #expect(abs(second.start - 2) < 0.05)
        #expect(abs(second.end - 3) < 0.05)
    }

    @Test("sub-100 ms blip is dropped as noise")
    func subMinDurationDropped() {
        let analyzer = Analyzer(config: AnalyzerConfig(padding: 0, minSegmentDuration: 0.1))
        // 50 ms of tone surrounded by silence.
        let samples = silence(seconds: 0.5) + tone(seconds: 0.05) + silence(seconds: 0.5)
        let segments = analyzer.detectSpeech(samples: samples, sampleRate: sampleRate)
        #expect(segments.isEmpty)
    }

    @Test("padding extends segment boundaries and clamps to file duration")
    func padding() {
        let padding: TimeInterval = 0.2
        let analyzer = Analyzer(config: AnalyzerConfig(padding: padding))
        let samples = silence(seconds: 0.5) + tone(seconds: 1) + silence(seconds: 0.5)
        let segments = analyzer.detectSpeech(samples: samples, sampleRate: sampleRate)
        let segment = try! #require(segments.first)
        #expect(segments.count == 1)
        // Tone runs roughly [0.5, 1.5]; padding should expand by ~0.2 each side.
        #expect(segment.start <= 0.5 - padding + 0.05)
        #expect(segment.start >= 0.5 - padding - 0.05)
        #expect(segment.end >= 1.5 + padding - 0.05)
        #expect(segment.end <= 2.0)  // clamped to file duration
    }

    @Test("short gaps between speech are merged")
    func shortGapsMerged() {
        let analyzer = Analyzer(
            config: AnalyzerConfig(minSilenceDuration: 0.5, padding: 0))
        // Two tones separated by 200 ms of silence — should merge into one.
        let samples = tone(seconds: 0.5) + silence(seconds: 0.2) + tone(seconds: 0.5)
        let segments = analyzer.detectSpeech(samples: samples, sampleRate: sampleRate)
        #expect(segments.count == 1)
    }
}
