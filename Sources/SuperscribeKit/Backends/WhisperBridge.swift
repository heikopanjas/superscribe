/// Bridging helpers that extract plain values from WhisperKit types.
///
/// `TranscriptionResult` here resolves to WhisperKit's class (our type
/// was renamed to `SegmentTranscription` to avoid the collision).
import Foundation
@preconcurrency import WhisperKit

/// A word extracted from WhisperKit results, free of any WhisperKit types.
struct WKWord: Sendable {
    let text: String
    let start: Float
    let end: Float
}

/// Extract words from WhisperKit's `[TranscriptionResult]`.
///
/// Returns plain value types so the caller doesn't need to touch
/// WhisperKit's `TranscriptionResult` class directly.
func extractWords(from results: [TranscriptionResult]) -> [WKWord] {
    var words: [WKWord] = []
    for result in results {
        for segment in result.segments {
            if let wordTimings = segment.words {
                for wt in wordTimings {
                    let text = wt.word.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { continue }
                    words.append(WKWord(text: text, start: wt.start, end: wt.end))
                }
            }
            else {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                words.append(WKWord(text: text, start: segment.start, end: segment.end))
            }
        }
    }
    return words
}
