import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Shared CLI behavior", .serialized, ResetSharedStateTrait())
struct CLIConsolidationTests {
    enum Outcome: CaseIterable, Sendable {
        case success
        case failure
        case cancellation
    }

    @Test func cliDefaultsFollowLibraryConfiguration() throws -> Void {
        let transcribe = try TranscribeOptions.parse([])
        #expect(transcribe.analyzerConfig == AnalyzerConfig())
        let pipeline = transcribe.pipelineRunOptions(tracks: [])
        #expect(pipeline.useCache == true)
        #expect(pipeline.isolationModel == nil)
        let merge = try MergeOptions.parse([]).renderConfiguration
        let rendering = RenderConfiguration()
        #expect(merge.format == rendering.format)
        #expect(merge.includeWords == rendering.includeWords)
        #expect(merge.gapThreshold == MergerConfig().gapThreshold)
        #expect(try ParakeetBackend().modelId == ParakeetBackend.defaultModelId)
    }

    @Test(arguments: [false, true])
    func pipelineOptionsPreserveFlagsAndResolvedTracks(template: Bool) throws -> Void {
        let options = try TranscribeOptions.parse([
            "--track", "Alice=alice.wav", "--mixed", "panel.wav", "--backend", "whisper.cpp", "--model", "base",
            "--language", "de", "--prompt", "context", "--silence-threshold=-35", "--min-silence", "1.25", "--padding", "0.3",
            "--no-cache", "--isolate", "--fine-tune"
        ])
        let tracks =
            if template == true { [TrackInput(speaker: "Mapped", file: URL(fileURLWithPath: "/mapped.wav"), diarization: TrackDiarization(speakerNames: ["Bob"]))] }
            else { options.trackInputs }
        let pipeline = options.pipelineRunOptions(tracks: tracks)
        #expect(pipeline.cliBackend == .whisperCpp)
        #expect(pipeline.cliModel == "base")
        #expect(pipeline.transcriptionConfig.language == "de")
        #expect(pipeline.transcriptionConfig.prompt == "context")
        #expect(pipeline.analyzerConfig == AnalyzerConfig(silenceThresholdDB: -35, minSilenceDuration: 1.25, padding: 0.3))
        #expect(pipeline.useCache == false)
        #expect(pipeline.isolationModel == .htdemucsFT)
        #expect(pipeline.tracks.map(\.speaker) == tracks.map(\.speaker))
        #expect(pipeline.tracks.map(\.file) == tracks.map(\.file))
        #expect(pipeline.tracks.last?.diarization?.speakerNames == tracks.last?.diarization?.speakerNames)
    }

    @Test(arguments: [false, true])
    func renderedOutputPreservesBytes(file: Bool) throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let destination = root.appendingPathComponent("transcript.txt")
            try "previous".write(to: destination, atomically: true, encoding: .utf8)
            let output = "Alice: Grüße 世界\n"
            var standardOutput: [String] = []
            try writeRenderedOutput(output, to: file ? destination.path : nil, writeToStandardOutput: { standardOutput.append($0) })
            if file == true {
                #expect(try String(contentsOf: destination, encoding: .utf8) == output)
                #expect(standardOutput.isEmpty == true)
            }
            else {
                #expect(standardOutput == [output])
                #expect(try String(contentsOf: destination, encoding: .utf8) == "previous")
            }
        }
    }

    @Test func failedOutputWritePropagatesWithoutPrinting() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            var printed = false
            #expect(throws: CocoaError.self) {
                try writeRenderedOutput("text", to: root.appendingPathComponent("missing/output.txt").path, writeToStandardOutput: { _ in printed = true })
            }
            #expect(printed == false)
        }
    }

    @Test(arguments: Outcome.allCases)
    func downloadScopeClearsOutputAfterEveryOutcome(outcome: Outcome) async throws -> Void {
        let output = TestDependencyStorage<[String]>([])
        let write: @Sendable (String) -> Void = { output[\.self].append($0) }
        do {
            let value = try await ModelManager.withDownloadProgress(write: write) { progress in
                progress(
                    DownloadProgress(
                        modelId: "model", backend: .whisperCpp, currentFile: "weights.bin", filesCompleted: 0, filesTotal: 1, bytesCompleted: 0, bytesTotal: 1, bytesPerSecond: nil))
                #expect(output[\.self].count == 1)
                switch outcome {
                    case .success: return 7
                    case .failure: throw TestError.fail
                    case .cancellation: throw CancellationError()
                }
            }
            #expect(outcome == .success)
            #expect(value == 7)
        }
        catch TestError.fail { #expect(outcome == .failure) }
        catch is CancellationError { #expect(outcome == .cancellation) }
        #expect(output[\.self].count == 2)
        #expect(output[\.self].first?.contains("Downloading") == true)
        #expect(output[\.self].last == "\r\u{1B}[K")
    }
}
