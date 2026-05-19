import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("WhisperBackend", .serialized, ResetSharedStateTrait())
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

    @Test func transcribeExtractsWordsFromSyntheticAPI() async throws {
        WhisperBackend.testUseStubLoad = true
        WhisperBackend.testWhisperAPISegments = [
            [
                WhisperTestToken(token: " hello", id: 1, t0: 0, t1: 50),
                WhisperTestToken(token: " world", id: 2, t0: 50, t1: 100)
            ]
        ]

        let backend = WhisperBackend(model: "stub-words")
        let out = try await backend.transcribe(
            samples: [Float](repeating: 0, count: 16_000),
            segment: SpeechSegment(start: 0, end: 1.0),
            config: TranscriptionConfig(language: "en", model: "stub-words", prompt: "Testing.")
        )
        #expect(out.words.isEmpty == false)
    }

    @Test func diskLoadSuccessUsesInjectedContextPointer() async throws {
        try await TestHelpers.withIsolatedModelCaches { _, _ in
            WhisperBackend.testUseStubLoad = false
            let modelId = "stub-disk-load"
            let binURL = WhisperBackend.installPath(for: modelId)
            try FileManager.default.createDirectory(
                at: binURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("not-a-real-ggml-model".utf8).write(to: binURL)
            defer { try? FileManager.default.removeItem(at: binURL) }

            WhisperBackend.testWhisperInitPointer = OpaquePointer(bitPattern: 0x4)!
            WhisperBackend.testWhisperStatePointer = OpaquePointer(bitPattern: 0x8)!
            WhisperBackend.testWhisperAPISegments = [
                [
                    WhisperTestToken(token: " ok", id: 1, t0: 0, t1: 10)
                ]
            ]
            defer {
                WhisperBackend.testWhisperInitPointer = nil
                WhisperBackend.testWhisperStatePointer = nil
                WhisperBackend.testWhisperAPISegments = nil
            }

            let backend = WhisperBackend(model: modelId)
            let out = try await backend.transcribe(
                samples: [Float](repeating: 0, count: 16_000),
                segment: SpeechSegment(start: 0, end: 0.5),
                config: TranscriptionConfig(language: "en", model: modelId, prompt: nil)
            )
            #expect(out.words.isEmpty == false)
        }
    }

    @Test func exerciseManagedContextReleaseForTesting() {
        WhisperBackend.exerciseManagedContextReleaseForTesting()
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
            { session in
                WhisperBackend.overrideRemoteModelsSession = session
                let models = try await WhisperBackend.remoteModels()
                #expect(models.contains(where: { $0.id == "tiny" }) == true)
            }
        )
    }
}
