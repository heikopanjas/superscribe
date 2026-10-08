import Foundation

/// NVIDIA Nemotron 3 Diarization (FluidAudio Core ML, up to eight speakers) over file-backed 16 kHz mono PCM.
public struct NemotronDiarizer: Diarizer {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var openSession: (@Sendable (URL) async throws -> any DiarizationSession)?
    }

    /// Test hook replacing the Core ML session.
    internal static var openSession: (@Sendable (URL) async throws -> any DiarizationSession)? {
        get { return Self.testState[\.openSession] }
        set { Self.testState[\.openSession] = newValue }
    }

    /// Seconds of audio read per streaming step; bounds memory independently of recording length.
    internal static let windowSeconds = 30

    private let modelDirectory: URL

    /// - Parameter modelDirectory: Installed model location; defaults to `DiarizerModel.installPath()`.
    /// - Throws: `CocoaError` when the default install path cannot be resolved.
    public init(modelDirectory: URL? = nil) throws {
        self.modelDirectory = try modelDirectory ?? DiarizerModel.installPath()
    }

    public func speakerActivity(in audio: PreparedAudio) async throws -> SpeakerActivity {
        guard audio.format == .asr16kMono else { throw AudioPreparerError.unsupportedFormat(audio.url) }
        let open = Self.openSession ?? NemotronLiveDiarizationSession.open
        let session = try await open(self.modelDirectory)
        let buffers = AudioBuffers.dependencies
        return try await BlockingWorker(label: "superscribe.diarize").run { cancellation in
            return try AudioBuffers.$dependencies.withValue(buffers) {
                let window = Self.windowSeconds * audio.format.sampleRate
                let total = Int(audio.frameCount)
                let frames = (Double(total) / Double(audio.format.sampleRate) / session.frameDuration).rounded(.up)
                var probabilities: [Float] = []
                probabilities.reserveCapacity((Int(frames) + 1) * session.speakerCount)
                for start in stride(from: 0, to: total, by: window) {
                    try cancellation.check()
                    probabilities += try session.append(try audio.samples(in: start ..< start + window))
                }
                probabilities += try session.finish()
                return try SpeakerActivity(probabilities: probabilities, speakerCount: session.speakerCount, frameDuration: session.frameDuration)
            }
        }
    }
}
