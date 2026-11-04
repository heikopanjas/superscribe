import Foundation

/// Selectable speaker-diarization backend.
public enum DiarizerBackend: String, CaseIterable, Codable, Sendable {
    case nemotron

    public var capabilities: BackendCapabilities {
        switch self {
            case .nemotron:
                return BackendCapabilities(
                    requiredAudioFormat: .asr16kMono,
                    displayName: "Nemotron 3 (FluidAudio Core ML)", defaultModelId: DiarizerModel.id)
        }
    }

    public func makeDiarizer() throws -> any Diarizer {
        switch self {
            case .nemotron: return try NemotronDiarizer()
        }
    }
}
