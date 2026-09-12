import Foundation
import whisper

// MARK: - Errors

enum WhisperError: Error, LocalizedError {
    case contextInitFailed(path: String)
    case stateInitFailed
    case unsupportedLanguage(String)
    case transcriptionFailed(code: Int32)

    var errorDescription: String? {
        switch self {
            case .contextInitFailed(let p): return "whisper_context init failed for model at \(p)"
            case .unsupportedLanguage(let language): return "Unsupported Whisper language: \(language)"
            case .stateInitFailed: return "whisper_init_state returned nil"
            case .transcriptionFailed(let c): return "whisper_full_with_state failed (code \(c))"
        }
    }
}
