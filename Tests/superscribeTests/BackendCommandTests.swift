import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Backend type management", .serialized, ResetSharedStateTrait())
struct BackendCommandTests {
    @Test func settingEachDefaultPreservesOtherPreferences() async throws -> Void {
        try UserConfig(defaultModels: ["parakeet": "v2"], defaultBackend: "whisper.cpp").save()
        var isolator = try BackendCommand.parse(["--isolator", "--set-default", "htdemucs"])
        try await isolator.run()
        var config = try UserConfig.load()
        #expect(config.defaultBackend == "whisper.cpp")
        #expect(config.defaultIsolatorBackend == "htdemucs")
        #expect(config.defaultDiarizerBackend == nil)

        var diarizer = try BackendCommand.parse(["--diarizer", "--set-default", "nemotron"])
        try await diarizer.run()
        config = try UserConfig.load()
        #expect(config.defaultBackend == "whisper.cpp")
        #expect(config.defaultIsolatorBackend == "htdemucs")
        #expect(config.defaultDiarizerBackend == "nemotron")

        var transcriber = try BackendCommand.parse(["--transcriber", "--set-default", "parakeet"])
        try await transcriber.run()
        config = try UserConfig.load()
        #expect(config.defaultBackend == "parakeet")
        #expect(config.defaultIsolatorBackend == "htdemucs")
        #expect(config.defaultDiarizerBackend == "nemotron")
        #expect(config.defaultModel(for: .parakeet) == "v2")
    }

    @Test(arguments: [
        ["--isolator", "--set-default", "parakeet"],
        ["--diarizer", "--set-default", "htdemucs"],
        ["--transcriber", "--set-default", "nemotron"]
    ])
    func rejectsBackendIdsFromOtherTypes(_ arguments: [String]) -> Void {
        do {
            _ = try BackendCommand.parse(arguments)
            Issue.record("Expected a backend-type validation error")
        }
        catch {
            #expect(BackendCommand.message(for: error).contains("Unknown backend") == true)
        }
    }
}
