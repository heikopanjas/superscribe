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
public struct SegmentTranscription: Sendable, Hashable {
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

// MARK: - Backend capabilities

/// Describes what a transcription backend supports and requires.
public struct BackendCapabilities: Sendable {
    /// The PCM audio format the backend requires.
    public let requiredAudioFormat: AudioFormat
    /// Human-readable name for logging / UI.
    public let displayName: String
    /// Built-in fall-back model id for this backend (used when neither the
    /// user nor the CLI supplied one). The authoritative model catalog lives
    /// remotely and is exposed via `ModelRegistry`.
    public let defaultModelId: String

    public init(
        requiredAudioFormat: AudioFormat,
        displayName: String,
        defaultModelId: String
    ) {
        self.requiredAudioFormat = requiredAudioFormat
        self.displayName = displayName
        self.defaultModelId = defaultModelId
    }
}

// MARK: - Model info

/// Describes a model published in a remote catalog (Hugging Face Hub).
public struct RemoteModelInfo: Sendable, Codable, Hashable {
    /// Short identifier the user passes to `--model` (e.g. `"v3"`,
    /// `"large-v3_turbo"`). May be a passed-through repo name when no
    /// short alias is known.
    public let id: String
    /// Hugging Face repo id (e.g. `"ggerganov/whisper.cpp"`).
    public let repoId: String
    /// Optional sub-folder within the repo that contains this model
    /// (e.g. `"openai_whisper-large-v3_turbo"`). `nil` when the model is
    /// the entire repo.
    public let subpath: String?
    /// Total size in bytes across all files of the model, when known.
    public let totalSizeBytes: Int64?
    /// Number of files comprising the model, when known.
    public let fileCount: Int?
    /// Last-modified timestamp of the source repo, when known.
    public let lastModified: Date?
    /// Canonical URL to the model on Hugging Face.
    public let repoURL: URL

    public init(
        id: String,
        repoId: String,
        subpath: String? = nil,
        totalSizeBytes: Int64? = nil,
        fileCount: Int? = nil,
        lastModified: Date? = nil,
        repoURL: URL
    ) {
        self.id = id
        self.repoId = repoId
        self.subpath = subpath
        self.totalSizeBytes = totalSizeBytes
        self.fileCount = fileCount
        self.lastModified = lastModified
        self.repoURL = repoURL
    }
}

/// Describes a model that is currently installed on disk for a backend.
public struct InstalledModelInfo: Sendable, Codable, Hashable {
    /// Short identifier the user passes to `--model`.
    public let id: String
    /// Filesystem location of the installed model.
    public let path: URL
    /// Total size in bytes on disk, when computable.
    public let sizeBytes: Int64?

    public init(id: String, path: URL, sizeBytes: Int64? = nil) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
    }
}

// MARK: - Enums for CLI options

/// Selectable transcription backend.
public enum Backend: String, CaseIterable, Sendable, Codable {
    case parakeet
    case whisperCpp = "whisper.cpp"
    case appleSpeech
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
