import Foundation

/// Selectable vocal-isolation backend, independent of the model variant.
public enum IsolatorBackend: String, CaseIterable, Codable, Sendable {
    case htdemucs

    public var capabilities: BackendCapabilities {
        switch self {
            case .htdemucs:
                return BackendCapabilities(
                    requiredAudioFormat: AudioFormat(sampleRate: 44_100, channels: 2),
                    displayName: "HTDemucs (DemucsMLX)", defaultModelId: IsolatorModel.htdemucs.rawValue)
        }
    }

    public func makeIsolator(model: IsolatorModel) throws -> any VocalIsolator {
        switch self {
            case .htdemucs: return try DemucsVocalIsolator(model: model)
        }
    }
}
