import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("BackendManager", .serialized, ResetSharedStateTrait())
struct BackendManagerTests {
    @Test func cliBackendOverridesConfig() throws -> Void {
        let config = UserConfig(defaultBackend: Backend.whisperCpp.rawValue)
        let backend = try BackendManager.resolveBackend(cliBackend: .parakeet, config: config)
        #expect(backend == .parakeet)
    }

    @Test func configBackendWhenCLINil() throws -> Void {
        let config = UserConfig(defaultBackend: Backend.whisperCpp.rawValue)
        let backend = try BackendManager.resolveBackend(cliBackend: nil, config: config)
        #expect(backend == .whisperCpp)
    }

    @Test func builtInDefaultWhenConfigUnset() throws -> Void {
        let config = UserConfig()
        let backend = try BackendManager.resolveBackend(cliBackend: nil, config: config)
        #expect(backend == .parakeet)
    }

    @Test func explicitModelOverridesConfig() throws -> Void {
        let config = UserConfig(defaultModels: [Backend.parakeet.rawValue: "v2"])
        let (_, model) = try BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: "v3", config: config
        )
        #expect(model == "v3")
    }

    @Test func configModelWhenCLINil() throws -> Void {
        let config = UserConfig(defaultModels: [Backend.parakeet.rawValue: "v2"])
        let (_, model) = try BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: nil, config: config
        )
        #expect(model == "v2")
    }

    @Test func builtInDefaultModelWhenNothingSet() throws -> Void {
        let config = UserConfig()
        let (_, model) = try BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: nil, config: config
        )
        #expect(model == ParakeetBackend.defaultModelId)
    }
}
