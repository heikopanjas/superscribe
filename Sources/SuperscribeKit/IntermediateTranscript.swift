import Foundation

/// Persisted intermediate transcript: the checkpoint between the
/// `transcribe` and `merge` phases. Hand-editable JSON.
public struct IntermediateTranscript: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let session: String?
    public let created: Date
    public let tracks: [Track]
    public let metadata: Metadata

    public init(
        session: String?,
        created: Date = Date(),
        tracks: [Track],
        metadata: Metadata,
        version: Int = IntermediateTranscript.currentVersion
    ) {
        self.version = version
        self.session = session
        self.created = created
        self.tracks = tracks
        self.metadata = metadata
    }

    public struct Track: Codable, Sendable {
        public let speaker: String
        public let file: String
        public let segments: [TranscribedSegment]

        public init(speaker: String, file: String, segments: [TranscribedSegment]) {
            self.speaker = speaker
            self.file = file
            self.segments = segments
        }
    }

    public struct TranscribedSegment: Codable, Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let words: [TimedWord]

        public init(start: TimeInterval, end: TimeInterval, words: [TimedWord]) {
            self.start = start
            self.end = end
            self.words = words
        }
    }

    public struct Metadata: Codable, Sendable {
        public let backend: Backend
        public let model: String
        public let language: String?
        public let analyzer: AnalyzerSettings

        public init(
            backend: Backend,
            model: String,
            language: String?,
            analyzer: AnalyzerSettings
        ) {
            self.backend = backend
            self.model = model
            self.language = language
            self.analyzer = analyzer
        }
    }

    public struct AnalyzerSettings: Codable, Sendable {
        public let silenceThresholdDB: Double
        public let minSilence: TimeInterval
        public let padding: TimeInterval

        enum CodingKeys: String, CodingKey {
            case silenceThresholdDB = "silence_threshold_db"
            case minSilence = "min_silence"
            case padding
        }

        public init(silenceThresholdDB: Double, minSilence: TimeInterval, padding: TimeInterval) {
            self.silenceThresholdDB = silenceThresholdDB
            self.minSilence = minSilence
            self.padding = padding
        }
    }
}

extension IntermediateTranscript {
    /// JSON encoder configured for the on-disk format: pretty-printed,
    /// stable key order, ISO-8601 timestamps.
    public static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
