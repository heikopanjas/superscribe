import Foundation

public struct SRTFormatter: TranscriptFormatter {
    public var includeWords: Bool
    public var maxLineLength: Int?

    public init(includeWords: Bool = false, maxLineLength: Int? = nil) {
        self.includeWords = includeWords
        self.maxLineLength = maxLineLength
    }

    public func render(_ segments: [MergedSegment]) throws -> String {
        try RenderConfiguration.validateLineLength(self.maxLineLength)
        let normalized = try TranscriptValidation.normalized(segments)
        let cues =
            self.includeWords
            ? normalized.flatMap { segment in
                segment.words.map { MergedSegment(speaker: segment.speaker, start: $0.start, end: $0.end, words: [$0], paragraphBreak: false) }
            } : normalized
        return MergedSegment.chronological(cues).enumerated().map { index, segment in
            let (start, end) = SubtitleTimestamp.bounds(segment)
            let label = TimedWord(text: "[\(segment.speaker)]", start: segment.start, end: segment.start)
            let body = SubtitleText.wrap([label] + segment.words, maximum: self.maxLineLength) { _, text in SubtitleText.escape(text) }
            return "\(index + 1)\n\(SubtitleTimestamp.string(milliseconds: start, comma: true)) --> \(SubtitleTimestamp.string(milliseconds: end, comma: true))\n\(body)\n\n"
        }.joined()
    }
}
