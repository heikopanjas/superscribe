import AVFoundation
import Foundation

/// Detects contiguous spans of speech in an audio file by RMS thresholding.
public struct Analyzer: Sendable {
    public let config: AnalyzerConfig

    public init(config: AnalyzerConfig = AnalyzerConfig()) {
        self.config = config
    }

    public func detectSpeech(in url: URL) throws -> [SpeechSegment] {
        let prepared = try AudioPreparer(targetFormat: .asr16kMono).prepare(url: url)
        return try self.detectSpeech(in: prepared)
    }

    public func detectSpeech(in audio: PreparedAudio) throws -> [SpeechSegment] {
        let file = try AVAudioFile(forReading: audio.url)
        return try self.detectSpeech(count: Int(audio.frameCount), sampleRate: Double(audio.format.sampleRate)) { start, count in
            let buffer = try AudioBuffers.make(format: file.processingFormat, frames: AudioValidation.frameCount(Double(count)))
            let channel = try AudioBuffers.channels(buffer)[0]
            file.framePosition = Int64(start)
            try AudioFileReading.read(file, into: buffer, count: AVAudioFrameCount(count))

            return Array(UnsafeBufferPointer(start: channel, count: count))
        }
    }

    public func detectSpeech(samples: [Float], sampleRate: Double) throws -> [SpeechSegment] {
        return try self.detectSpeech(count: samples.count, sampleRate: sampleRate) { start, count in
            return Array(samples[start ..< start + count])
        }
    }

    private func detectSpeech(count: Int, sampleRate: Double, read: (Int, Int) throws -> [Float]) throws -> [SpeechSegment] {
        try self.config.validate()
        guard sampleRate.isFinite == true, sampleRate > 0 else { throw AudioPreparerError.conversionFailed("Sample rate must be finite and positive") }
        let totalDuration = Double(count) / sampleRate
        let threshold = Float(pow(10, self.config.silenceThresholdDB / 20))
        var raw: [SpeechSegment] = []
        var start: Int?
        var index = 0
        while index < count {
            try Task.checkCancellation()
            let length = min(self.config.windowSize, count - index)
            let samples = try read(index, length)
            let speech = Self.rms(samples, from: 0, to: length) >= threshold
            if speech == true, start == nil {
                start = index
            }
            else if speech == false, let beginning = start {
                raw.append(SpeechSegment(start: Double(beginning) / sampleRate, end: Double(index) / sampleRate))
                start = nil
            }
            index += length
        }
        if let start { raw.append(SpeechSegment(start: Double(start) / sampleRate, end: totalDuration)) }
        return Self.mergeShortGaps(raw, minGap: self.config.minSilenceDuration).map {
            SpeechSegment(start: max(0, $0.start - self.config.padding), end: min(totalDuration, $0.end + self.config.padding))
        }.filter { $0.duration >= self.config.minSegmentDuration }
    }

    // MARK: - Helpers

    internal static func rms(_ samples: [Float], from start: Int, to end: Int) -> Float {
        guard end > start else { return 0 }
        var sumSquares: Float = 0
        for i in start ..< end {
            let sample = samples[i]
            sumSquares += sample * sample
        }
        return (sumSquares / Float(end - start)).squareRoot()
    }

    private static func mergeShortGaps(
        _ segments: [SpeechSegment],
        minGap: TimeInterval
    ) -> [SpeechSegment] {
        guard let first = segments.first else { return [] }
        var result: [SpeechSegment] = [first]
        for segment in segments.dropFirst() {
            let last = result[result.count - 1]
            if segment.start - last.end < minGap {
                result[result.count - 1] = SpeechSegment(start: last.start, end: segment.end)
            }
            else {
                result.append(segment)
            }
        }
        return result
    }

    internal static func readMonoFloat32(from url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { throw AnalyzerError.readFailed(url, underlying: error) }
        let rate = file.processingFormat.sampleRate
        return (try AudioPreparer(targetFormat: AudioFormat(sampleRate: try AudioValidation.sampleRate(rate), channels: 1)).loadAndConvert(url: url), rate)
    }
}
