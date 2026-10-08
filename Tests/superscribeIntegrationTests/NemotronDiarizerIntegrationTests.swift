import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Explicit Nemotron diarization hardware integration", .serialized)
struct NemotronDiarizerIntegrationTests {
    /// Requires an installed diarizer and a recording with at least two voices.
    @Test func separatesSpeakersInProvidedMixedRecording() async throws -> Void {
        let path = try #require(ProcessInfo.processInfo.environment["SUPERSCRIBE_INTEGRATION_MIXED_AUDIO"])
        let audio = try AudioPreparer(targetFormat: .asr16kMono).prepare(url: URL(fileURLWithPath: path))
        let activity = try await NemotronDiarizer().speakerActivity(in: audio)
        let duration = Double(audio.frameCount) / Double(audio.format.sampleRate)
        #expect(abs(Double(activity.frameCount) * activity.frameDuration - duration) < 0.1)
        let speakers = SpeakerTurnBuilder.speakers(from: activity, duration: duration, config: AnalyzerConfig())
        #expect(speakers.count >= 2)
    }
}
