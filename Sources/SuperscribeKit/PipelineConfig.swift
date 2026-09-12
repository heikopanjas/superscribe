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

    public init(
        tracks: [TrackInput],
        backend: Backend = .parakeet,
        transcriptionConfig: TranscriptionConfig,
        analyzerConfig: AnalyzerConfig = AnalyzerConfig(),
        maxConcurrentTranscriptions: Int = 2,
        maxConcurrentConversions: Int = 2,
        session: String? = nil
    ) {
        self.tracks = tracks
        self.backend = backend
        self.transcriptionConfig = transcriptionConfig
        self.analyzerConfig = analyzerConfig
        self.maxConcurrentTranscriptions = maxConcurrentTranscriptions
        self.maxConcurrentConversions = maxConcurrentConversions
        self.session = session
    }
}
