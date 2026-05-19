import Foundation

/// A speaker track to be transcribed: a human-readable name and the path
/// to its audio file.
public struct TrackInput: Sendable {
    public let speaker: String
    public let file: URL

    public init(speaker: String, file: URL) {
        self.speaker = speaker
        self.file = file
    }
}

/// Configuration for the full transcription pipeline.
public struct PipelineConfig: Sendable {
    public let tracks: [TrackInput]
    public let backend: Backend
    public let transcriptionConfig: TranscriptionConfig
    public let analyzerConfig: AnalyzerConfig
    /// Maximum concurrent transcription calls (default 2 for ANE).
    public let maxConcurrentTranscriptions: Int
    /// Optional session label stored in the intermediate transcript.
    public let session: String?

    public init(
        tracks: [TrackInput],
        backend: Backend = .parakeet,
        transcriptionConfig: TranscriptionConfig,
        analyzerConfig: AnalyzerConfig = AnalyzerConfig(),
        maxConcurrentTranscriptions: Int = 2,
        session: String? = nil
    ) {
        self.tracks = tracks
        self.backend = backend
        self.transcriptionConfig = transcriptionConfig
        self.analyzerConfig = analyzerConfig
        self.maxConcurrentTranscriptions = maxConcurrentTranscriptions
        self.session = session
    }
}

/// Progress update emitted after each segment is transcribed.
public struct TranscriptionProgress: Sendable {
    /// Speaker name of the current track.
    public let speaker: String
    /// 1-based index of the completed segment within the track.
    public let segmentIndex: Int
    /// Total segments in the current track.
    public let totalSegments: Int
    /// Running total of completed segments across all tracks.
    public let overallCompleted: Int
    /// Total segments across all tracks.
    public let overallTotal: Int
}

/// Orchestrates silence detection → transcription → intermediate transcript.
public struct TranscribePipeline: Sendable {
    private let transcriber: any Transcriber
    private let config: PipelineConfig
    private let onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    private let onConversionProgress: (@Sendable (ConversionProgress) -> Void)?
    private let audioCache: ConvertedAudioCache?

    public init(
        transcriber: any Transcriber,
        config: PipelineConfig,
        audioCache: ConvertedAudioCache? = nil,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)? = nil,
        onConversionProgress: (@Sendable (ConversionProgress) -> Void)? = nil
    ) {
        self.transcriber = transcriber
        self.config = config
        self.audioCache = audioCache
        self.onProgress = onProgress
        self.onConversionProgress = onConversionProgress
    }

    /// Run the full pipeline and return the intermediate transcript.
    public func run() async throws -> IntermediateTranscript {
        let analyzer = Analyzer(config: config.analyzerConfig)
        let preparer = AudioPreparer(for: transcriber.capabilities, cache: audioCache)
        let targetSampleRate = Double(transcriber.capabilities.requiredAudioFormat.sampleRate)
        let conversionProgress = onConversionProgress

        // Phase 1: load + convert each track, then detect speech (parallel).
        let trackData: [(TrackInput, [Float], [SpeechSegment])] =
            try await withThrowingTaskGroup(
                of: (TrackInput, [Float], [SpeechSegment]).self
            ) { group in
                for track in config.tracks {
                    group.addTask {
                        let samples = try preparer.loadAndConvert(
                            url: track.file,
                            onProgress: conversionProgress
                        )
                        let segments = analyzer.detectSpeech(
                            samples: samples,
                            sampleRate: targetSampleRate
                        )
                        return (track, samples, segments)
                    }
                }
                var results: [(TrackInput, [Float], [SpeechSegment])] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }

        // Phase 2: transcribe segments with bounded concurrency.
        let overallTotal = trackData.reduce(0) { $0 + $1.2.count }
        var overallCompleted = 0
        var transcribedTracks: [IntermediateTranscript.Track] = []

        for (track, samples, segments) in trackData {
            let baseCompleted = overallCompleted
            let transcribedSegments = try await transcribeSegments(
                segments,
                allSamples: samples,
                preparer: preparer,
                onSegmentDone: { segIdx in
                    let done = baseCompleted + segIdx + 1
                    self.onProgress?(
                        TranscriptionProgress(
                            speaker: track.speaker,
                            segmentIndex: segIdx + 1,
                            totalSegments: segments.count,
                            overallCompleted: done,
                            overallTotal: overallTotal
                        ))
                }
            )
            overallCompleted += segments.count
            if transcribedSegments.isEmpty == false {
                transcribedTracks.append(
                    IntermediateTranscript.Track(
                        speaker: track.speaker,
                        file: track.file.path,
                        segments: transcribedSegments
                    )
                )
            }
        }

        return IntermediateTranscript(
            session: config.session,
            tracks: transcribedTracks,
            metadata: .init(
                backend: config.backend,
                model: config.transcriptionConfig.model,
                language: config.transcriptionConfig.language,
                analyzer: .init(
                    silenceThresholdDB: config.analyzerConfig.silenceThresholdDB,
                    minSilence: config.analyzerConfig.minSilenceDuration,
                    padding: config.analyzerConfig.padding
                )
            )
        )
    }

    // MARK: - Private

    internal func transcribeSegments(
        _ segments: [SpeechSegment],
        allSamples: [Float],
        preparer: AudioPreparer,
        onSegmentDone: (@Sendable (Int) -> Void)? = nil
    ) async throws -> [IntermediateTranscript.TranscribedSegment] {
        let indexedSegments = Array(segments.enumerated())
        let results = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(
            limit: config.maxConcurrentTranscriptions,
            items: indexedSegments
        ) { indexed in
            let (idx, segment) = indexed
            let segmentSamples = preparer.slice(allSamples, segment: segment)
            let result: SegmentTranscription
            if segmentSamples.isEmpty == true {
                result = SegmentTranscription(segment: segment, words: [])
            }
            else {
                result = try await self.transcriber.transcribe(
                    samples: segmentSamples,
                    segment: segment,
                    config: self.config.transcriptionConfig
                )
            }
            onSegmentDone?(idx)
            return (idx, result)
        }

        return results.compactMap { pair in
            let result = pair.1
            guard result.words.isEmpty == false else { return nil }
            return IntermediateTranscript.TranscribedSegment(
                start: result.segment.start,
                end: result.segment.end,
                words: result.words
            )
        }
    }
}
