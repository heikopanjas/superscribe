import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ModelInstallationError", .serialized, ResetSharedStateTrait())
struct ModelInstallationErrorTests {

    @Test func modelNotInstalledMessageNamesInstallCommand() throws -> Void {
        let err = ModelInstallationError.modelNotInstalled(model: "tiny", backend: .whisperCpp)
        let msg = err.description
        #expect(msg.contains("Whisper"))
        #expect(msg.contains("tiny"))
        #expect(msg.contains("superscribe models --download tiny --backend whisper"))
    }

    @Test func unknownModelListsAvailable() throws -> Void {
        let err = ModelInstallationError.unknownModel(
            model: "bogus", backend: .parakeet, available: ["v2", "v3"]
        )
        let msg = err.description
        #expect(msg.contains("bogus"))
        #expect(msg.contains("v2, v3"))
    }

    @Test func unknownModelEmptyCatalogMessage() throws -> Void {
        let err = ModelInstallationError.unknownModel(
            model: "missing", backend: .whisperCpp, available: []
        )
        #expect(err.description.contains("(catalog empty)") == true)
    }

}
