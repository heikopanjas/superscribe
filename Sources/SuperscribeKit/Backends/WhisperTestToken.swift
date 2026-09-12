import Foundation
import whisper

/// Synthetic whisper token for unit tests (avoids on-disk GGML models).
internal struct WhisperTestToken: Sendable {
    let token: String
    let id: Int32
    let t0: Int64
    let t1: Int64
}
