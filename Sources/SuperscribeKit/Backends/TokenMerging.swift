import Foundation

/// Accumulates sub-word ASR tokens (SentencePiece ▁ or leading-space boundaries)
/// into whole-word `TimedWord`s with a shared segment offset.
public struct TokenAccumulator: Sendable {
    private var words: [TimedWord] = []
    private var currentText = ""
    private var wordStart: TimeInterval = 0
    private var wordEnd: TimeInterval = 0

    public init() {}

    /// Ingest one token with its start/end times relative to the segment.
    public mutating func accept(token: String, start: TimeInterval, end: TimeInterval) {
        let isNewWord = token.hasPrefix("▁") || token.hasPrefix(" ")

        if isNewWord == true && currentText.isEmpty == false {
            flush()
        }

        let cleaned =
            token
            .replacingOccurrences(of: "▁", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " "))

        guard cleaned.isEmpty == false else { return }

        if currentText.isEmpty == true {
            wordStart = start
        }
        currentText += cleaned
        wordEnd = end
    }

    /// Returns accumulated words, applying `segmentOffset` to each time span.
    public consuming func finish(segmentOffset: TimeInterval) -> [TimedWord] {
        flush()
        return words.map {
            TimedWord(
                text: $0.text,
                start: $0.start + segmentOffset,
                end: $0.end + segmentOffset
            )
        }
    }

    private mutating func flush() {
        guard currentText.isEmpty == false else { return }
        words.append(
            TimedWord(
                text: currentText,
                start: wordStart,
                end: wordEnd
            ))
        currentText = ""
    }
}
