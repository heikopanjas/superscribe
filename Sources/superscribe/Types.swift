import Foundation

// MARK: - Speech & transcription primitives

/// A single recognised word with its time interval inside the source audio.
public struct TimedWord: Codable, Sendable, Hashable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A contiguous span of speech detected in a single audio track.
public struct SpeechSegment: Codable, Sendable, Hashable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
}

/// The result of transcribing a single `SpeechSegment`.
public struct TranscriptionResult: Sendable, Hashable {
    public let segment: SpeechSegment
    public let words: [TimedWord]

    public init(segment: SpeechSegment, words: [TimedWord]) {
        self.segment = segment
        self.words = words
    }
}

/// Per-call configuration passed to a `Transcriber`.
public struct TranscriptionConfig: Sendable, Hashable {
    public let language: String?
    public let model: String
    public let prompt: String?

    public init(language: String?, model: String, prompt: String?) {
        self.language = language
        self.model = model
        self.prompt = prompt
    }
}

// MARK: - Merge pipeline types

/// A speech segment annotated with its speaker.
public struct AttributedSegment: Sendable, Hashable {
    public let speaker: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let words: [TimedWord]

    public init(speaker: String, start: TimeInterval, end: TimeInterval, words: [TimedWord]) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.words = words
    }
}

/// A segment after overlap resolution, gap detection and coalescing.
public struct MergedSegment: Sendable, Hashable {
    public let speaker: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var words: [TimedWord]
    public let paragraphBreak: Bool

    public init(
        speaker: String,
        start: TimeInterval,
        end: TimeInterval,
        words: [TimedWord],
        paragraphBreak: Bool
    ) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.words = words
        self.paragraphBreak = paragraphBreak
    }
}

// MARK: - Enums for CLI options

/// Selectable transcription backend. `auto` lets the tool choose the best
/// available backend for the host system.
public enum Backend: String, CaseIterable, Sendable, Codable {
    case whisper, mlx, speech, openai, auto
}

/// Strategy for handling time-overlapping segments from different speakers
/// (i.e. crosstalk).
public enum OverlapPolicy: String, CaseIterable, Sendable, Codable {
    case preserve, trim, interleave
}

/// Output format for the merged transcript.
public enum OutputFormat: String, CaseIterable, Sendable, Codable {
    case vtt, srt, json, txt
}
