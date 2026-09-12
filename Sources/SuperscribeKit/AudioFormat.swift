import Foundation

// MARK: - Audio format

/// Describes the PCM audio format a backend expects its input in.
public struct AudioFormat: Sendable, Hashable {
    /// Sample rate in Hz (e.g. 16000).
    public let sampleRate: Int
    /// Number of channels (1 = mono).
    public let channels: Int

    public init(sampleRate: Int, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    /// 16 kHz mono — the most common ASR input format.
    public static let asr16kMono = AudioFormat(sampleRate: 16_000, channels: 1)
}
