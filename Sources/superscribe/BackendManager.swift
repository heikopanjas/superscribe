import ArgumentParser
import Foundation
import SuperscribeKit

/// Resolves backends + models and constructs transcribers.
final class BackendManager {
    private init() {}

    /// Resolves the effective backend and model from CLI options + user config.
    ///
    /// Priority: explicit CLI flag > user config > built-in defaults.
    static func resolveBackendAndModel(
        cliBackend: Backend?,
        cliModel: String?
    ) -> (backend: Backend, model: String) {
        let config = UserConfig.load()

        let backend = cliBackend ?? config.resolvedDefaultBackend()

        let model: String
        if let explicit = cliModel {
            model = explicit
        }
        else if let saved = config.defaultModel(for: backend) {
            model = saved
        }
        else {
            // Built-in defaults sourced from each backend's ModelRegistry.
            model = builtInDefaultModel(for: backend)
        }

        return (backend, model)
    }

    /// Returns the built-in default model id for a backend.
    static func builtInDefaultModel(for backend: Backend) -> String {
        switch backend {
            case .parakeet: return ParakeetBackend.defaultModelId
            case .whisperCpp: return WhisperBackend.defaultModelId
            case .appleSpeech: return ""
        }
    }

    /// Returns a `Transcriber` for the given backend + model.
    static func makeTranscriber(backend: Backend, model: String) throws -> any Transcriber {
        switch backend {
            case .parakeet:
                guard ParakeetBackend.isAvailable == true else {
                    throw BackendError.unavailable("Parakeet requires Apple Silicon")
                }
                return ParakeetBackend(model: model)
            case .whisperCpp:
                guard WhisperBackend.isAvailable == true else {
                    throw BackendError.unavailable("Whisper requires Apple Silicon")
                }
                return WhisperBackend(model: model)
            case .appleSpeech:
                throw BackendError.unavailable("Apple Speech backend not yet implemented (requires macOS 26)")
        }
    }
}

enum BackendError: Error, CustomStringConvertible {
    case unavailable(String)
    var description: String {
        switch self {
            case .unavailable(let msg): return msg
        }
    }
}
