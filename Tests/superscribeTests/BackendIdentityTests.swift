import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Backend instance identity", .serialized, ResetSharedStateTrait())
struct BackendIdentityTests {
    @Test func identityBelongsToBackendInstance() async throws -> Void {
        #expect(try ParakeetBackend(model: "ja").modelId == "tdt-ja")
        if #available(macOS 26, *) {
            let backend = try AppleSpeechBackend()
            _ = await backend.modelId
            AppleSpeechBackend.testLoadHook = { .init(locale: Locale(identifier: "de-DE"), localeId: "de-DE") }
            _ = try await backend.transcribe(samples: [0], segment: .init(start: 0, end: 1), config: .init())
            #expect(await backend.modelId == "de-DE")
            let explicit = try AppleSpeechBackend(model: "en-US")
            #expect(await explicit.modelId == "en-US")
        }
    }
}
