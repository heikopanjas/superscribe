import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Analyzer", .serialized, ResetSharedStateTrait())
struct AnalyzerTests {
    private let sampleRate: Double = 48_000

    /// Generate a sine-wave tone at full amplitude.
    private func tone(seconds: Double, amplitude: Float = 0.5) -> [Float] {
        let count = Int(seconds * self.sampleRate)
        let twoPiOverRate = 2.0 * .pi * 440.0 / self.sampleRate
        return (0 ..< count).map { amplitude * Float(sin(twoPiOverRate * Double($0))) }
    }

    private func silence(seconds: Double) -> [Float] {
        return Array(repeating: 0, count: Int(seconds * self.sampleRate))
    }

    @Test("pure silence yields no segments")
    func pureSilence() throws -> Void {
        let analyzer = Analyzer()
        let segments = try analyzer.detectSpeech(samples: self.silence(seconds: 2), sampleRate: self.sampleRate)
        #expect(segments.isEmpty)
    }

    @Test("constant tone yields one segment spanning the file")
    func constantTone() throws -> Void {
        let analyzer = Analyzer()
        let samples = self.tone(seconds: 2)
        let segments = try analyzer.detectSpeech(samples: samples, sampleRate: self.sampleRate)
        let segment = try #require(segments.first)
        #expect(segments.count == 1)
        // With padding the segment may extend slightly beyond [0, 2] but is
        // clamped to file duration.
        #expect(segment.start == 0)
        #expect(segment.end == 2)
    }

    @Test("tone-silence-tone yields two segments with correct boundaries")
    func toneSilenceTone() throws -> Void {
        let analyzer = Analyzer(config: AnalyzerConfig(padding: 0))
        let samples = self.tone(seconds: 1) + self.silence(seconds: 1) + self.tone(seconds: 1)
        let segments = try analyzer.detectSpeech(samples: samples, sampleRate: self.sampleRate)
        #expect(segments.count == 2)
        let first = try #require(segments.first)
        let second = try #require(segments.last)
        #expect(abs(first.start - 0) < 0.05)
        #expect(abs(first.end - 1) < 0.05)
        #expect(abs(second.start - 2) < 0.05)
        #expect(abs(second.end - 3) < 0.05)
    }

    @Test("sub-100 ms blip is dropped as noise")
    func subMinDurationDropped() throws -> Void {
        let analyzer = Analyzer(config: AnalyzerConfig(padding: 0, minSegmentDuration: 0.1))
        // 50 ms of tone surrounded by silence.
        let samples = self.silence(seconds: 0.5) + self.tone(seconds: 0.05) + self.silence(seconds: 0.5)
        let segments = try analyzer.detectSpeech(samples: samples, sampleRate: self.sampleRate)
        #expect(segments.isEmpty)
    }

    @Test("padding extends segment boundaries and clamps to file duration")
    func padding() throws -> Void {
        let padding: TimeInterval = 0.2
        let analyzer = Analyzer(config: AnalyzerConfig(padding: padding))
        let samples = self.silence(seconds: 0.5) + self.tone(seconds: 1) + self.silence(seconds: 0.5)
        let segments = try analyzer.detectSpeech(samples: samples, sampleRate: self.sampleRate)
        let segment = try #require(segments.first)
        #expect(segments.count == 1)
        // Tone runs roughly [0.5, 1.5]; padding should expand by ~0.2 each side.
        #expect(segment.start <= 0.5 - padding + 0.05)
        #expect(segment.start >= 0.5 - padding - 0.05)
        #expect(segment.end >= 1.5 + padding - 0.05)
        #expect(segment.end <= 2.0)  // clamped to file duration
    }

    @Test("short gaps between speech are merged")
    func shortGapsMerged() throws -> Void {
        let analyzer = Analyzer(
            config: AnalyzerConfig(minSilenceDuration: 0.5, padding: 0))
        // Two tones separated by 200 ms of silence — should merge into one.
        let samples = self.tone(seconds: 0.5) + self.silence(seconds: 0.2) + self.tone(seconds: 0.5)
        let segments = try analyzer.detectSpeech(samples: samples, sampleRate: self.sampleRate)
        #expect(segments.count == 1)
    }

    @Test func emptySamplesReturnsNoSegments() throws -> Void {
        let analyzer = Analyzer()
        #expect(try analyzer.detectSpeech(samples: [], sampleRate: self.sampleRate).isEmpty == true)
    }

    @Test func nonPositiveSampleRateReturnsNoSegments() throws -> Void {
        let analyzer = Analyzer()
        #expect(throws: AudioPreparerError.self) { _ = try analyzer.detectSpeech(samples: [0.1], sampleRate: 0) }
    }

    @Test func rmsEmptyRangeReturnsZero() throws -> Void {
        #expect(Analyzer.rms([1.0], from: 2, to: 2) == 0)
    }

    @Test func emptyAudioFileReturnsNoSegments() throws -> Void {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format =
            (try #require(
                AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 16_000,
                    channels: 1,
                    interleaved: false
                )))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = (try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)))
        buffer.frameLength = 0
        try file.write(from: buffer)

        let analyzer = Analyzer()
        #expect(try analyzer.detectSpeech(in: url).isEmpty == true)
    }
}
