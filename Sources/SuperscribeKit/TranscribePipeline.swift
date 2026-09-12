import Foundation

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
        try TrackInput.validate(self.config.tracks)
        try self.config.analyzerConfig.validate()
        try self.config.transcriptionConfig.validate()
        guard self.config.maxConcurrentTranscriptions > 0, self.config.maxConcurrentConversions > 0 else { throw BoundedTaskGroupError.invalidLimit }
        let analyzer = Analyzer(config: self.config.analyzerConfig)
        let preparer = AudioPreparer(for: self.transcriber.capabilities, cache: self.audioCache)
        let conversionProgress = self.onConversionProgress
        let trackData = try await ConcurrencyHelpers.withBoundedThrowingTaskGroup(limit: self.config.maxConcurrentConversions, items: self.config.tracks) { track in
            let dependencies = SuperscribeKitTestHooks.testState
            let buffers = AudioBuffers.dependencies
            let locks = FileTransaction.lockOperation
            return try await BlockingWorker(label: "superscribe.audio.prepare").run { cancellation in
                return try SuperscribeKitTestHooks.$testState.withValue(dependencies) {
                    return try AudioBuffers.$dependencies.withValue(buffers) {
                        return try FileTransaction.$lockOperation.withValue(locks) {
                            let audio = try preparer.prepare(url: track.file, onProgress: conversionProgress, checkCancellation: cancellation.check)
                            let segments = try analyzer.detectSpeech(in: audio)
                            return (audio, segments)
                        }
                    }
                }
            }
        }
        let jobs = trackData.enumerated().flatMap { trackIndex, data in
            data.1.enumerated().map { (trackIndex, $0.offset, $0.element) }
        }
        var results = trackData.map { [IntermediateTranscript.TranscribedSegment?](repeating: nil, count: $0.1.count) }
        var completed = 0
        try await ConcurrencyHelpers.collect(
            limit: self.config.maxConcurrentTranscriptions, items: jobs,
            body: { job in
                let (trackIndex, _, segment) = job
                let buffers = AudioBuffers.dependencies
                let samples = try await BlockingWorker(label: "superscribe.audio.segment").run { _ in
                    return try AudioBuffers.$dependencies.withValue(buffers) {
                        return try trackData[trackIndex].0.samples(in: segment)
                    }
                }
                return try await self.transcribe(samples: samples, segment: segment)
            },
            onResult: { index, result in
                let (trackIndex, segmentIndex, _) = jobs[index]
                results[trackIndex][segmentIndex] = Self.transcribedSegment(result)
                completed += 1
                self.onProgress?(
                    TranscriptionProgress(
                        speaker: self.config.tracks[trackIndex].speaker, segmentIndex: segmentIndex + 1, totalSegments: trackData[trackIndex].1.count, overallCompleted: completed,
                        overallTotal: jobs.count))
            })
        let transcribedTracks = self.config.tracks.enumerated().compactMap { index, track -> IntermediateTranscript.Track? in
            let segments = results[index].compactMap { $0 }
            if segments.isEmpty == true { return nil }
            return IntermediateTranscript.Track(speaker: track.speaker, file: track.file.path, segments: segments)
        }

        return IntermediateTranscript(
            session: self.config.session,
            tracks: transcribedTracks,
            metadata: .init(
                backend: self.config.backend,
                model: await self.transcriber.modelId,
                language: self.config.transcriptionConfig.language,
                analyzer: .init(
                    silenceThresholdDB: self.config.analyzerConfig.silenceThresholdDB,
                    minSilence: self.config.analyzerConfig.minSilenceDuration,
                    padding: self.config.analyzerConfig.padding
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
            limit: self.config.maxConcurrentTranscriptions,
            items: indexedSegments
        ) { indexed in
            let (idx, segment) = indexed
            let segmentSamples = try preparer.slice(allSamples, segment: segment)
            let result = try await self.transcribe(samples: segmentSamples, segment: segment)
            onSegmentDone?(idx)
            return (idx, result)
        }

        return results.compactMap { Self.transcribedSegment($0.1) }
    }

    private func transcribe(samples: [Float], segment: SpeechSegment) async throws -> SegmentTranscription {
        if samples.isEmpty == true { return SegmentTranscription(segment: segment, words: []) }
        return try await self.transcriber.transcribe(samples: samples, segment: segment, config: self.config.transcriptionConfig)
    }

    private static func transcribedSegment(_ result: SegmentTranscription) -> IntermediateTranscript.TranscribedSegment? {
        if result.words.isEmpty == true { return nil }
        return IntermediateTranscript.TranscribedSegment(start: result.segment.start, end: result.segment.end, words: result.words)
    }
}
