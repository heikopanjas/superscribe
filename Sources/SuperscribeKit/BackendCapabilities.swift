import Foundation

// MARK: - Backend capabilities

/// Describes what a transcription backend supports and requires.
public struct BackendCapabilities: Sendable {
    /// The PCM audio format the backend requires.
    public let requiredAudioFormat: AudioFormat
    /// Human-readable name for logging / UI.
    public let displayName: String
    /// Built-in fall-back model id for this backend (used when neither the
    /// user nor the CLI supplied one). The authoritative model catalog lives
    /// remotely and is exposed via `ModelRegistry`.
    public let defaultModelId: String

    public init(
        requiredAudioFormat: AudioFormat,
        displayName: String,
        defaultModelId: String
    ) {
        self.requiredAudioFormat = requiredAudioFormat
        self.displayName = displayName
        self.defaultModelId = defaultModelId
    }
}
