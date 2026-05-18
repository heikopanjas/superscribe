import Foundation

/// A backend that converts speech audio into timestamped words.
public protocol Transcriber: Sendable {
    /// Whether this backend is usable on the current host.
    static var isAvailable: Bool { get }

    /// The backend's capabilities, including its required audio format.
    var capabilities: BackendCapabilities { get }

    /// Transcribe a single speech segment from pre-converted audio samples.
    ///
    /// - Parameters:
    ///   - samples: PCM Float32 samples in the format declared by
    ///     `capabilities.requiredAudioFormat`.
    ///   - segment: The time span within the original track this slice
    ///     corresponds to.
    ///   - config: Per-call transcription configuration.
    func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription
}
