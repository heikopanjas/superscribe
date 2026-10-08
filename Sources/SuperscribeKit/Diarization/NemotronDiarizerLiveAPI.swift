import FluidAudio
import Foundation

/// FluidAudio Nemotron 3 calls only; orchestration lives in `NemotronDiarizer`.
/// The non-Sendable diarizer is created here and afterwards used solely on one serial `BlockingWorker`.
internal final class NemotronLiveDiarizationSession: DiarizationSession, @unchecked Sendable {
    private static let config = DiarizerModel.config

    private let diarizer: Nemotron3Diarizer

    private init(diarizer: Nemotron3Diarizer) {
        self.diarizer = diarizer
    }

    /// Loads the installed Core ML model and opens a streaming session.
    internal static let open: @Sendable (URL) async throws -> any DiarizationSession = { directory in
        let models = try await Nemotron3Models.load(config: NemotronLiveDiarizationSession.config, directory: directory)
        return NemotronLiveDiarizationSession(diarizer: Nemotron3Diarizer(config: NemotronLiveDiarizationSession.config, models: models))
    }

    internal var speakerCount: Int { return Self.config.numSpeakers }

    internal var frameDuration: TimeInterval { return TimeInterval(Self.config.outputFrameSeconds) }

    internal func append(_ samples: [Float]) throws -> [Float] {
        self.diarizer.appendAudio(samples)
        return try self.diarizer.processBufferedAudio().flatMap(\.probabilities)
    }

    internal func finish() throws -> [Float] {
        return try self.diarizer.finishStream().flatMap(\.probabilities)
    }
}
