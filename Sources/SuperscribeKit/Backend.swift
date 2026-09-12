import Foundation

// MARK: - Enums for CLI options

/// Selectable transcription backend.
public enum Backend: String, CaseIterable, Sendable, Codable {
    case parakeet
    case whisperCpp = "whisper.cpp"
    case appleSpeech
}
