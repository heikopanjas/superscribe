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
