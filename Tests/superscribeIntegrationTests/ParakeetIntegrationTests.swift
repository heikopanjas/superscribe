import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Explicit Parakeet hardware integration", .serialized)
struct ParakeetIntegrationTests {
    @Test func transcribesProvidedRecording() async throws -> Void {
        let path = try #require(ProcessInfo.processInfo.environment["SUPERSCRIBE_INTEGRATION_AUDIO"])
        let model = ProcessInfo.processInfo.environment["SUPERSCRIBE_INTEGRATION_MODEL"] ?? "v3"
        let backend = try ParakeetBackend(model: model)
        let samples = try AudioPreparer(for: backend.capabilities).loadAndConvert(url: URL(fileURLWithPath: path))
        #expect(samples.isEmpty == false)
        let result = try await backend.transcribe(
            samples: samples,
            segment: SpeechSegment(start: 0, end: Double(samples.count) / 16_000),
            config: TranscriptionConfig(language: nil, prompt: nil)
        )
        #expect(result.words.isEmpty == false)
    }
}
