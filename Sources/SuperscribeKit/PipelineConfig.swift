import Foundation

/// Configuration for the full transcription pipeline.
public struct PipelineConfig: Sendable {
    public let tracks: [TrackInput]
    public let backend: Backend
    public let transcriptionConfig: TranscriptionConfig
    public let analyzerConfig: AnalyzerConfig
    /// Maximum concurrent transcription calls (default 2 for ANE).
    public let maxConcurrentTranscriptions: Int
    public let maxConcurrentConversions: Int
    /// Optional session label stored in the intermediate transcript.
    public let session: String?
    /// Separates speakers in tracks marked with `TrackInput.diarization`; required when any track is mixed.
    public let diarizer: (any Diarizer)?
    /// Optional local vocal isolation, applied before speech detection or diarization.
    public let isolator: (any VocalIsolator)?

    public init(
        tracks: [TrackInput],
        backend: Backend = .parakeet,
        transcriptionConfig: TranscriptionConfig,
        analyzerConfig: AnalyzerConfig = AnalyzerConfig(),
        maxConcurrentTranscriptions: Int = 2,
        maxConcurrentConversions: Int = 2,
        session: String? = nil,
        diarizer: (any Diarizer)? = nil,
        isolator: (any VocalIsolator)? = nil
    ) {
        self.tracks = tracks
        self.backend = backend
        self.transcriptionConfig = transcriptionConfig
        self.analyzerConfig = analyzerConfig
        self.maxConcurrentTranscriptions = maxConcurrentTranscriptions
        self.maxConcurrentConversions = maxConcurrentConversions
        self.session = session
        self.diarizer = diarizer
        self.isolator = isolator
    }
}
