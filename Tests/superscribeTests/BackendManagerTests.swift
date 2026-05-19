import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("BackendManager")
struct BackendManagerTests {
    @Test func cliBackendOverridesConfig() {
        let config = UserConfig(defaultBackend: Backend.whisperCpp.rawValue)
        let backend = BackendManager.resolveBackend(cliBackend: .parakeet, config: config)
        #expect(backend == .parakeet)
    }

    @Test func configBackendWhenCLINil() {
        let config = UserConfig(defaultBackend: Backend.whisperCpp.rawValue)
        let backend = BackendManager.resolveBackend(cliBackend: nil, config: config)
        #expect(backend == .whisperCpp)
    }

    @Test func builtInDefaultWhenConfigUnset() {
        let config = UserConfig()
        let backend = BackendManager.resolveBackend(cliBackend: nil, config: config)
        #expect(backend == .parakeet)
    }

    @Test func explicitModelOverridesConfig() {
        let config = UserConfig(defaultModels: [Backend.parakeet.rawValue: "v2"])
        let (_, model) = BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: "v3", config: config
        )
        #expect(model == "v3")
    }

    @Test func configModelWhenCLINil() {
        let config = UserConfig(defaultModels: [Backend.parakeet.rawValue: "v2"])
        let (_, model) = BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: nil, config: config
        )
        #expect(model == "v2")
    }

    @Test func builtInDefaultModelWhenNothingSet() {
        let config = UserConfig()
        let (_, model) = BackendManager.resolveBackendAndModel(
            cliBackend: .parakeet, cliModel: nil, config: config
        )
        #expect(model == ParakeetBackend.defaultModelId)
    }
}
