import AVFoundation
import Foundation

/// Configuration for silence-based speech detection.
public struct AnalyzerConfig: Sendable, Hashable {
    /// RMS threshold in dB below which audio is considered silence.
    public var silenceThresholdDB: Double

    /// Minimum duration of silence to split segments. Shorter silences are
    /// merged into the surrounding speech.
    public var minSilenceDuration: TimeInterval

    /// Padding added before and after detected speech to avoid clipping
    /// onsets and tails.
    public var padding: TimeInterval

    /// RMS window size in samples. At 48 kHz, 1024 ≈ 21 ms.
    public var windowSize: Int

    /// Segments shorter than this are dropped as noise.
    public var minSegmentDuration: TimeInterval

    public init(
        silenceThresholdDB: Double = -40.0,
        minSilenceDuration: TimeInterval = 0.5,
        padding: TimeInterval = 0.15,
        windowSize: Int = 1024,
        minSegmentDuration: TimeInterval = 0.1
    ) {
        self.silenceThresholdDB = silenceThresholdDB
        self.minSilenceDuration = minSilenceDuration
        self.padding = padding
        self.windowSize = windowSize
        self.minSegmentDuration = minSegmentDuration
    }
}

/// Errors raised by `Analyzer`.
public enum AnalyzerError: Error, CustomStringConvertible {
    case unsupportedFormat(URL)
    case readFailed(URL, underlying: Error)

    public var description: String {
        switch self {
            case .unsupportedFormat(let url):
                return "Unsupported audio format: \(url.path)"
            case .readFailed(let url, let underlying):
                return "Failed to read audio file \(url.path): \(underlying)"
        }
    }
}

/// Detects contiguous spans of speech in an audio file by RMS thresholding.
public struct Analyzer: Sendable {
    public let config: AnalyzerConfig

    public init(config: AnalyzerConfig = AnalyzerConfig()) {
        self.config = config
    }

    /// Detect speech segments in the given audio file.
    public func detectSpeech(in url: URL) throws -> [SpeechSegment] {
        let (samples, sampleRate) = try Self.readMonoFloat32(from: url)
        return detectSpeech(samples: samples, sampleRate: sampleRate)
    }

    /// Detect speech in pre-decoded mono float samples. Public for testability.
    public func detectSpeech(samples: [Float], sampleRate: Double) -> [SpeechSegment] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }

        let window = max(1, config.windowSize)
        let totalDuration = TimeInterval(samples.count) / sampleRate
        let thresholdLinear = pow(10.0, config.silenceThresholdDB / 20.0)

        // Walk the buffer in non-overlapping windows. A window is "speech" if
        // its RMS is at or above the threshold. Track on/off transitions to
        // produce raw segments in sample space.
        var rawSegments: [(startSample: Int, endSample: Int)] = []
        var inSpeech = false
        var segmentStart = 0
        var index = 0

        while index < samples.count {
            let windowEnd = min(index + window, samples.count)
            let isSpeech = Self.rms(samples, from: index, to: windowEnd) >= Float(thresholdLinear)
            if isSpeech, !inSpeech {
                segmentStart = index
                inSpeech = true
            }
            else if !isSpeech, inSpeech {
                rawSegments.append((segmentStart, index))
                inSpeech = false
            }
            index = windowEnd
        }
        if inSpeech {
            rawSegments.append((segmentStart, samples.count))
        }

        // Convert to time-space, merge gaps shorter than minSilenceDuration,
        // pad, clamp to [0, totalDuration], then drop too-short segments.
        let timed = rawSegments.map {
            SpeechSegment(
                start: TimeInterval($0.startSample) / sampleRate,
                end: TimeInterval($0.endSample) / sampleRate
            )
        }
        let merged = Self.mergeShortGaps(timed, minGap: config.minSilenceDuration)
        let padded = merged.map {
            SpeechSegment(
                start: max(0, $0.start - config.padding),
                end: min(totalDuration, $0.end + config.padding)
            )
        }
        return padded.filter { $0.duration >= config.minSegmentDuration }
    }

    // MARK: - Helpers

    private static func rms(_ samples: [Float], from start: Int, to end: Int) -> Float {
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

    /// Read an audio file and return its samples as mono Float32 along with
    /// the sample rate.
    static func readMonoFloat32(from url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        }
        catch {
            throw AnalyzerError.readFailed(url, underlying: error)
        }

        let sourceFormat = file.processingFormat
        guard
            let monoFloatFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceFormat.sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw AnalyzerError.unsupportedFormat(url)
        }

        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return ([], sourceFormat.sampleRate) }

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)
        else {
            throw AnalyzerError.unsupportedFormat(url)
        }

        do {
            try file.read(into: sourceBuffer)
        }
        catch {
            throw AnalyzerError.readFailed(url, underlying: error)
        }

        // Fast path: already mono Float32.
        if sourceFormat.commonFormat == .pcmFormatFloat32, sourceFormat.channelCount == 1,
            let channel = sourceBuffer.floatChannelData
        {
            let count = Int(sourceBuffer.frameLength)
            return (Array(UnsafeBufferPointer(start: channel[0], count: count)), sourceFormat.sampleRate)
        }

        // Otherwise convert to mono Float32 via AVAudioConverter.
        guard let converter = AVAudioConverter(from: sourceFormat, to: monoFloatFormat),
            let monoBuffer = AVAudioPCMBuffer(
                pcmFormat: monoFloatFormat, frameCapacity: frameCount)
        else {
            throw AnalyzerError.unsupportedFormat(url)
        }

        var sourceConsumed = false
        var conversionError: NSError?
        let status = converter.convert(to: monoBuffer, error: &conversionError) { _, statusOut in
            if sourceConsumed {
                statusOut.pointee = .endOfStream
                return nil
            }
            sourceConsumed = true
            statusOut.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw AnalyzerError.readFailed(url, underlying: conversionError)
        }
        guard status != .error, let channel = monoBuffer.floatChannelData else {
            throw AnalyzerError.unsupportedFormat(url)
        }

        let count = Int(monoBuffer.frameLength)
        return (Array(UnsafeBufferPointer(start: channel[0], count: count)), sourceFormat.sampleRate)
    }
}
