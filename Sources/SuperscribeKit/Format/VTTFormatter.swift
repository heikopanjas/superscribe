import Foundation

public struct VTTFormatter: TranscriptFormatter {
    public var includeWords: Bool
    public var maxLineLength: Int?

    public init(includeWords: Bool = false, maxLineLength: Int? = nil) {
        self.includeWords = includeWords
        self.maxLineLength = maxLineLength
    }

    public func render(_ segments: [MergedSegment]) throws -> String {
        try RenderConfiguration.validateLineLength(self.maxLineLength)
        var output = "WEBVTT\n"
        for segment in try TranscriptValidation.normalized(segments) {
            let (start, end) = SubtitleTimestamp.bounds(segment)
            var previous = start
            let body = SubtitleText.wrap(segment.words, maximum: self.maxLineLength) { index, text in
                let escaped = SubtitleText.escape(text)
                guard self.includeWords == true, index >= 0 else { return escaped }
                let timestamp = SubtitleTimestamp.milliseconds(segment.words[index].start)
                guard timestamp > previous, timestamp < end else { return escaped }
                previous = timestamp
                return "<\(SubtitleTimestamp.string(milliseconds: timestamp))>\(escaped)"
            }
            let speaker = segment.speaker.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            output += "\n\(SubtitleTimestamp.string(milliseconds: start)) --> \(SubtitleTimestamp.string(milliseconds: end))\n<v \(SubtitleText.escape(speaker))>\(body)\n"
        }
        return output
    }

    internal static func timestamp(_ seconds: TimeInterval) -> String {
        return SubtitleTimestamp.string(milliseconds: SubtitleTimestamp.milliseconds(max(0, seconds)))
    }
}
