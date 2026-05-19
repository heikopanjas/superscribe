import ArgumentParser
import Foundation
import SuperscribeKit

/// Resolves backends + models and constructs transcribers.
final class BackendManager {
    private init() {}

    /// Resolves the effective backend from CLI options + user config.
    ///
    /// Priority: explicit CLI flag > user config > built-in default.
    static func resolveBackend(
        cliBackend: Backend?,
        config: UserConfig = UserConfig.load()
    ) -> Backend {
        if let cliBackend {
            return cliBackend
        }
        return config.resolvedDefaultBackend()
    }

    /// Resolves the effective backend and model from CLI options + user config.
    ///
    /// Priority: explicit CLI flag > user config > built-in defaults.
    static func resolveBackendAndModel(
        cliBackend: Backend?,
        cliModel: String?,
        config: UserConfig = UserConfig.load()
    ) -> (backend: Backend, model: String) {
        let backend = resolveBackend(cliBackend: cliBackend, config: config)

        let model: String
        if let explicit = cliModel {
            model = explicit
        }
        else if let saved = config.defaultModel(for: backend) {
            model = saved
        }
        else {
            model = backend.registryDefaultModelId
        }

        return (backend, model)
    }

    /// Returns the built-in default model id for a backend.
    static func builtInDefaultModel(for backend: Backend) -> String {
        backend.registryDefaultModelId
    }

    /// Returns a `Transcriber` for the given backend + model.
    static func makeTranscriber(backend: Backend, model: String) throws -> any Transcriber {
        try backend.makeTranscriber(model: model)
    }
}
