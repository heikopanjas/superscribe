import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("PipelineRunner", .serialized, ResetSharedStateTrait())
struct PipelineRunnerTests {
    @Test func runUsesInjectedDependencies() async throws -> Void {
        let audioURL = try TestHelpers.makeTempSineWAV(name: "runner", durationSeconds: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let probe = PipelineRunProbe()

        let deps = PipelineRunner.Dependencies(
            resolveBackendAndModel: { _, _ in (.parakeet, "mock") },
            ensureModelInstalled: { _, _ in },
            makeTranscriber: { _, _ in MockTranscriber() },
            logBackend: { backend, _ in probe.setBackend(backend) },
            clearProgressLine: { probe.markCleared() }
        )

        let result = try await PipelineRunner.run(
            options: PipelineRunOptions(
                cliBackend: nil,
                cliModel: nil,
                tracks: [TrackInput(speaker: "A", file: audioURL)],
                transcriptionConfig: TranscriptionConfig(language: "en", prompt: nil),
                analyzerConfig: AnalyzerConfig(),
                useCache: false
            ),
            dependencies: deps
        )

        #expect(probe.backend == .parakeet)
        #expect(probe.clearedProgress == true)
        #expect(result.backend == .parakeet)
        #expect(result.model == "mock")
        #expect(result.transcript.tracks.isEmpty == false)
        #expect(result.duration >= 0)
    }
}
