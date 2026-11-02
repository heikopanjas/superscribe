import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Isolation pipeline", .serialized, ResetSharedStateTrait())
struct IsolationPipelineTests {
    @Test func isolatesOrdinaryAndMixedTracksPreservingOriginalPaths() async throws -> Void {
        let source = try TestHelpers.makeTemp16kMonoFloatWAV(name: "isolated-pipeline", durationSeconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let calls = Counter()
        let tracks = [TrackInput(speaker: "Host", file: source), TrackInput(speaker: "Panel", file: source, diarization: TrackDiarization())]
        let config = PipelineConfig(
            tracks: tracks, transcriptionConfig: TranscriptionConfig(language: "en", prompt: nil),
            diarizer: try StubDiarizer(slots: Array(repeating: 0, count: 200)), isolator: StubVocalIsolator(calls: calls))
        let transcript = try await TranscribePipeline(
            transcriber: MockTranscriber(), config: config,
            onIsolationProgress: { progress in
                #expect(progress.source == source)
                #expect(progress.fraction == 1)
            }
        ).run()
        #expect(await calls.value == 2)
        #expect(transcript.tracks.map(\.speaker) == ["Host", "Speaker 1"])
        #expect(transcript.tracks.allSatisfy { $0.file == source.path } == true)
    }

    @Test func runnerCreatesOnlyTheRequestedIsolator() async throws -> Void {
        let source = try TestHelpers.makeTemp16kMonoFloatWAV(name: "isolation-runner")
        defer { try? FileManager.default.removeItem(at: source) }
        let calls = Counter()
        var dependencies = PipelineRunner.Dependencies(
            resolveBackendAndModel: { _, _ in (.parakeet, "mock") }, ensureModelInstalled: { _, _ in },
            makeTranscriber: { _, _ in MockTranscriber() }, makeDiarizer: { try StubDiarizer(slots: []) },
            logBackend: { _, _ in }, clearProgressLine: {})
        dependencies.makeIsolator = { model in
            #expect(model == .htdemucsFT)
            return StubVocalIsolator(calls: calls)
        }
        let result = try await PipelineRunner.run(
            options: PipelineRunOptions(
                cliBackend: nil, cliModel: nil, tracks: [TrackInput(speaker: "A", file: source)],
                transcriptionConfig: TranscriptionConfig(language: "en", prompt: nil), analyzerConfig: AnalyzerConfig(),
                useCache: false, isolationModel: .htdemucsFT), dependencies: dependencies)
        #expect(await calls.value == 1)
        #expect(result.transcript.tracks.first?.file == source.path)
        #expect(throws: (any Error).self) { try RunCommand.parse(["--fine-tune"]) }
        let command = try RunCommand.parse(["--isolate", "--fine-tune"])
        #expect(command.transcribeOptions.isolationModel == .htdemucsFT)
    }
}
