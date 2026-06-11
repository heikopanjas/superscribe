import Foundation

/// Maps Apple Speech transcription spans into superscribe word timestamps.
enum AppleSpeechResultMapping {
    struct WordSpan: Sendable, Hashable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    static func map(spans: [WordSpan], segmentOffset: TimeInterval) -> [TimedWord] {
        spans.compactMap { span in
            let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return TimedWord(
                text: trimmed,
                start: span.start + segmentOffset,
                end: span.end + segmentOffset
            )
        }
    }
}
