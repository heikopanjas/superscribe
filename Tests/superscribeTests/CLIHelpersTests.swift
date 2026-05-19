import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("CLI helpers")
struct CLIHelpersTests {
    @Test func defaultIntermediateOutputPathUsesBackendWhenEmpty() {
        let path = defaultIntermediateOutputPath(backend: .whisperCpp, explicitOutput: "")
        #expect(path == "transcript.superscribe.whisper.cpp.json")
    }

    @Test func defaultIntermediateOutputPathHonorsExplicit() {
        let path = defaultIntermediateOutputPath(backend: .parakeet, explicitOutput: "custom.json")
        #expect(path == "custom.json")
    }

    @Test func saveIntermediateTranscriptWritesJSON() throws {
        let transcript = IntermediateTranscript(
            session: nil,
            tracks: [],
            metadata: IntermediateTranscript.Metadata(
                backend: .parakeet,
                model: "v3",
                language: "en",
                analyzer: IntermediateTranscript.AnalyzerSettings(
                    silenceThresholdDB: -40,
                    minSilence: 0.5,
                    padding: 0.15
                )
            )
        )
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("out-\(UUID().uuidString).json")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }

        try saveIntermediateTranscript(transcript, to: path)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try IntermediateTranscript.jsonDecoder().decode(IntermediateTranscript.self, from: data)
        #expect(decoded.metadata.model == "v3")
        #expect(decoded.metadata.backend == .parakeet)
    }

    @Test func formatBytesDelegatesToKit() {
        #expect(formatBytes(1024) == ByteFormatting.format(1024))
    }
}

@Suite("PipelineRunner")
struct PipelineRunnerTests {
    private func makeTempAudio() throws -> URL {
        let sampleRate: Double = 48_000
        let frameCount = AVAudioFrameCount(sampleRate * 2.0)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let floats = buffer.floatChannelData![0]
        let freq: Float = 440.0
        for i in 0 ..< Int(frameCount) {
            floats[i] = sinf(2.0 * .pi * freq * Float(i) / Float(sampleRate)) * 0.5
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    @Test func runUsesInjectedDependencies() async throws {
        let audioURL = try makeTempAudio()
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
                transcriptionConfig: { model in
                    TranscriptionConfig(language: "en", model: model, prompt: nil)
                },
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

private final class PipelineRunProbe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var backend: Backend?
    private(set) var clearedProgress = false

    func setBackend(_ backend: Backend) {
        lock.lock()
        self.backend = backend
        lock.unlock()
    }

    func markCleared() {
        lock.lock()
        clearedProgress = true
        lock.unlock()
    }
}
