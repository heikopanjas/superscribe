import Foundation

/// Bounded, file-backed Demucs vocal isolation with one reusable model session.
public final class DemucsVocalIsolator: VocalIsolator {
    @TaskLocal internal static var openSession: @Sendable (IsolatorModel, URL) async throws -> any VocalIsolationSession = IsolatorLiveAPI.open

    private let model: IsolatorModel
    private let directory: URL
    private let loader = LoadOnce<any VocalIsolationSession>()

    public init(model: IsolatorModel = .htdemucs, modelDirectory: URL? = nil) throws {
        self.model = model
        self.directory = try modelDirectory ?? model.installPath()
    }

    public func prepare(
        source: URL, targetFormat: AudioFormat, cache: ConvertedAudioCache? = nil,
        onProgress: (@Sendable (ConversionProgress) -> Void)? = nil
    ) async throws -> PreparedAudio {
        try AudioValidation.validate(targetFormat)
        try Task.checkCancellation()
        let identity = "demucs-0.1.0-\(self.model.rawValue)-r1"
        let key = cache?.key(for: source, targetFormat: targetFormat, processingIdentity: identity)
        let cached: PreparedAudio?
        if let cache, let key {
            cached = try await AudioBuffers.perform { _ in try cache.preparedAudio(for: key, format: targetFormat) }
        }
        else {
            cached = nil
        }
        if let audio = cached {
            onProgress?(ConversionProgress(source: source, framesProcessed: audio.frameCount, framesTotal: audio.frameCount, fraction: 1))
            return audio
        }
        let open = Self.openSession
        let session = try await self.loader.get { try await open(self.model, self.directory) }
        guard session.sampleRate > 0, session.sampleRate <= 192_000, (1 ... 2).contains(session.channels) == true else {
            throw InputValidationError("Isolation requires a positive sample rate up to 192 kHz and one or two channels")
        }
        let audio = try await IsolationAudioFile.open(source: source, sampleRate: session.sampleRate, channels: session.channels)
        let window = 30 * session.sampleRate
        let overlap = 2 * session.sampleRate
        var mixer = IsolationOverlap(frames: overlap)
        var start: Int64 = 0
        while start < audio.frameCount {
            try Task.checkCancellation()
            let count = min(window, Int(audio.frameCount - start))
            let input = try await audio.read(start: start, count: count)
            let samples = try await session.vocals(samples: input, frames: max(2, count))
            guard samples.count == max(2, count), samples.allSatisfy(\.isFinite) == true else {
                throw InputValidationError("Isolation returned invalid samples or changed the section duration")
            }
            let final = start + Int64(count) == audio.frameCount
            let completed = final ? audio.frameCount : start + Int64(count - overlap)
            try await audio.write(mixer.append(Array(samples.prefix(count)), final: final))
            onProgress?(ConversionProgress(source: source, framesProcessed: completed, framesTotal: audio.frameCount, fraction: Double(completed) / Double(audio.frameCount)))
            if final == true { break }
            start += Int64(window - overlap)
        }
        try await audio.close()
        return try await AudioBuffers.perform { cancellation in
            let preparer = AudioPreparer(targetFormat: targetFormat, cache: key == nil ? nil : cache)
            return try preparer.prepare(url: audio.vocalsURL, cacheKey: key, checkCancellation: cancellation.check)
        }
    }
}
