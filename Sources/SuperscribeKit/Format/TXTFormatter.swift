import Foundation

public struct TXTFormatter: TranscriptFormatter {
    public var includeWords: Bool
    public init(includeWords: Bool = false) { self.includeWords = includeWords }

    public func render(_ segments: [MergedSegment]) throws -> String {
        var output = ""
        for segment in try TranscriptValidation.normalized(segments) {
            if segment.paragraphBreak == true, output.isEmpty == false { output += "\n" }
            let body = segment.words.map { word in
                let prefix =
                    if self.includeWords == true { "[\(SubtitleTimestamp.string(milliseconds: SubtitleTimestamp.milliseconds(word.start)))] " }
                    else { "" }
                return prefix + word.text
            }.joined(separator: " ")
            output += "\(segment.speaker): \(body)\n"
        }
        return output
    }
}
