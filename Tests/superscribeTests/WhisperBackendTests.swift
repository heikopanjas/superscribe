import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("WhisperBackend")
struct WhisperBackendTests {

    @Test func whisperErrorDescriptions() {
        let ctx = WhisperError.contextInitFailed(path: "/tmp/x.bin")
        #expect(ctx.errorDescription?.contains("/tmp/x.bin") == true)

        let state = WhisperError.stateInitFailed
        #expect(state.errorDescription?.isEmpty == false)

        let tx = WhisperError.transcriptionFailed(code: -7)
        #expect(tx.errorDescription?.contains("-7") == true)
    }

    @Test func transcribeThrowsWhenBinMissing() async throws {
        let modelId = "model-absent-\(UUID().uuidString.prefix(8))"
        let path = WhisperBackend.installPath(for: modelId)
        #expect(FileManager.default.fileExists(atPath: path.path) == false)

        let backend = WhisperBackend(model: modelId)
        await #expect(throws: ModelInstallationError.self) {
            _ = try await backend.transcribe(
                samples: [0],
                segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: nil, model: modelId, prompt: nil)
            )
        }
    }

    @Test func transcribeMediumIntegrationWhenInstalled() async throws {
        let bin = WhisperBackend.installPath(for: "medium")
        guard FileManager.default.fileExists(atPath: bin.path) == true else {
            return
        }

        let wav = try TestHelpers.makeTempSineWAV(name: "whisper-medium-it", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: wav) }

        let whisper = WhisperBackend(model: "medium")
        let caps = whisper.capabilities
        let samples = try AudioPreparer(for: caps).loadAndConvert(url: wav)
        let backend = WhisperBackend(model: "medium")
        let cfg = TranscriptionConfig(language: "en", model: "medium", prompt: "Testing.")
        _ = try await backend.transcribe(
            samples: samples,
            segment: SpeechSegment(start: 0, end: 1.0),
            config: cfg
        )
    }

    @Test func invalidBinThrowsContextInitFailed() async throws {
        let modelId = "bad-bin-\(UUID().uuidString.prefix(8))"
        let url = WhisperBackend.installPath(for: modelId)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("not-a-real-ggml-model".utf8).write(to: url)

        let backend = WhisperBackend(model: modelId)
        await #expect(throws: WhisperError.self) {
            _ = try await backend.transcribe(
                samples: [Float](repeating: 0, count: 16_000),
                segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: "en", model: modelId, prompt: "x")
            )
        }
    }

    @Test func transcribeSpeechExtractsWordsWhenMediumInstalled() async throws {
        let bin = WhisperBackend.installPath(for: "medium")
        guard FileManager.default.fileExists(atPath: bin.path) == true else { return }

        let wav = try makeSpeechWAV()
        defer { try? FileManager.default.removeItem(at: wav) }

        let backend = WhisperBackend(model: "medium")
        let samples = try AudioPreparer(for: backend.capabilities).loadAndConvert(url: wav)
        let out = try await backend.transcribe(
            samples: samples,
            segment: SpeechSegment(start: 0, end: min(3.0, Double(samples.count) / 16_000)),
            config: TranscriptionConfig(language: "en", model: "medium", prompt: nil)
        )
        #expect(out.words.isEmpty == false)
    }

    @Test func publicRemoteModelsUsesSessionOverride() async throws {
        let info = """
            {"id":"ggerganov/whisper.cpp","lastModified":"2024-01-01T00:00:00Z","siblings":[
              {"rfilename":"ggml-tiny.bin","size":100}
            ]}
            """
        let prior = WhisperBackend.overrideRemoteModelsSession
        defer { WhisperBackend.overrideRemoteModelsSession = prior }
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(info.utf8))
            },
            {
                WhisperBackend.overrideRemoteModelsSession = URLSession.mocked()
                let models = try await WhisperBackend.remoteModels()
                #expect(models.contains(where: { $0.id == "tiny" }) == true)
            }
        )
    }

    private func makeSpeechWAV() throws -> URL {
        let dir = try TestHelpers.makeTempDir(prefix: "whisper-speech")
        let aiff = dir.appendingPathComponent("speech.aiff")
        let wav = dir.appendingPathComponent("speech.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", aiff.path, "Hello world, this is a speech recognition test."]
        try say.run()
        say.waitUntilExit()
        #expect(say.terminationStatus == 0)
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        convert.arguments = [aiff.path, wav.path, "-f", "WAVE", "-d", "LEI16@16000"]
        try convert.run()
        convert.waitUntilExit()
        #expect(convert.terminationStatus == 0)
        return wav
    }
}
