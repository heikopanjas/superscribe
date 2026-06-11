import Foundation

/// Central dispatch from `Backend` to per-backend registry and transcriber types.
extension Backend {
    public var registryDefaultModelId: String {
        switch self {
            case .parakeet: return ParakeetBackend.defaultModelId
            case .whisperCpp: return WhisperBackend.defaultModelId
            case .appleSpeech: return AppleSpeechCatalog.defaultModelId
        }
    }

    public func installPath(for modelId: String) throws -> URL {
        switch self {
            case .whisperCpp: return WhisperBackend.installPath(for: modelId)
            case .parakeet: return ParakeetBackend.installPath(for: modelId)
            case .appleSpeech: return try AppleSpeechCatalog.installPath(for: modelId)
        }
    }

    public func remoteModels() async throws -> [RemoteModelInfo] {
        switch self {
            case .parakeet: return try await ParakeetBackend.remoteModels()
            case .whisperCpp: return try await WhisperBackend.remoteModels()
            case .appleSpeech: return try await AppleSpeechCatalog.remoteModels()
        }
    }

    public func installedModels() async throws -> [InstalledModelInfo] {
        switch self {
            case .parakeet: return try ParakeetBackend.installedModels()
            case .whisperCpp: return try WhisperBackend.installedModels()
            case .appleSpeech: return try await AppleSpeechCatalog.installedModels()
        }
    }

    public func makeTranscriber(model: String) throws -> any Transcriber {
        switch self {
            case .parakeet:
                guard ParakeetBackend.isAvailable == true else {
                    throw BackendTranscriberError.unavailable("Parakeet requires Apple Silicon")
                }
                return ParakeetBackend(model: model)
            case .whisperCpp:
                guard WhisperBackend.isAvailable == true else {
                    throw BackendTranscriberError.unavailable("Whisper requires Apple Silicon")
                }
                return WhisperBackend(model: model)
            case .appleSpeech:
                return try makeAppleSpeechTranscriberDispatch(model: model)
        }
    }

    private func makeAppleSpeechTranscriberDispatch(model: String) throws -> any Transcriber {
        guard AppleSpeechSupport.isRuntimeAvailable() == true else {
            throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
        }
        guard AppleSpeechSupport.testForceAPIAvailabilityFalse == false else {
            throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
        }
        return try AppleSpeechTranscriberBridge.make(model: model)
    }
}

public enum BackendTranscriberError: Error, CustomStringConvertible, Sendable {
    case unavailable(String)

    public var description: String {
        switch self {
            case .unavailable(let msg): return msg
        }
    }
}
