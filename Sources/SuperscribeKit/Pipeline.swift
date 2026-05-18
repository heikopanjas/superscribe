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
    public let transcriptionConfig: TranscriptionConfig
    public let analyzerConfig: AnalyzerConfig
    /// Maximum concurrent transcription calls (default 2 for ANE).
    public let maxConcurrentTranscriptions: Int
    /// Optional session label stored in the intermediate transcript.
    public let session: String?

    public init(
        tracks: [TrackInput],
        transcriptionConfig: TranscriptionConfig,
        analyzerConfig: AnalyzerConfig = AnalyzerConfig(),
        maxConcurrentTranscriptions: Int = 2,
        session: String? = nil
    ) {
        self.tracks = tracks
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
            if !transcribedSegments.isEmpty {
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
                backend: .parakeet,
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

    private func transcribeSegments(
        _ segments: [SpeechSegment],
        allSamples: [Float],
        preparer: AudioPreparer,
        onSegmentDone: (@Sendable (Int) -> Void)? = nil
    ) async throws -> [IntermediateTranscript.TranscribedSegment] {
        try await withThrowingTaskGroup(
            of: (Int, SegmentTranscription).self
        ) { group in
            var inFlight = 0
            var nextIndex = 0
            var results: [(Int, SegmentTranscription)] = []

            while nextIndex < segments.count || !group.isEmpty {
                // Fill up to the concurrency limit.
                while inFlight < config.maxConcurrentTranscriptions,
                    nextIndex < segments.count
                {
                    let idx = nextIndex
                    let segment = segments[idx]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        let segmentSamples = preparer.slice(allSamples, segment: segment)
                        let result = try await self.transcriber.transcribe(
                            samples: segmentSamples,
                            segment: segment,
                            config: self.config.transcriptionConfig
                        )
                        return (idx, result)
                    }
                }

                // Wait for at least one to finish.
                if let result = try await group.next() {
                    results.append(result)
                    onSegmentDone?(result.0)
                    inFlight -= 1
                }
            }

            // Sort by original index, map to intermediate format, drop empty segments.
            return results.sorted { $0.0 < $1.0 }.compactMap { _, result in
                guard !result.words.isEmpty else { return nil }
                return IntermediateTranscript.TranscribedSegment(
                    start: result.segment.start,
                    end: result.segment.end,
                    words: result.words
                )
            }
        }
    }
}
