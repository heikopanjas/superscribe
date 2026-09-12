import Foundation

/// Splits at supplied word boundaries. An indivisible timed word may exceed the requested duration.
internal enum CueSplitter {
    internal static func split(_ segments: [MergedSegment], maximumDuration: TimeInterval?) throws -> [MergedSegment] {
        let normalized = try TranscriptValidation.normalized(segments)
        guard let limit = maximumDuration else { return normalized }
        guard limit.isFinite == true, limit > 0 else { throw InputValidationError("Maximum cue duration must be finite and positive") }
        let cues = normalized.flatMap { segment in
            if segment.end - segment.start <= limit || segment.words.count <= 1 { return [segment] }
            var result: [MergedSegment] = []
            var offset = 0
            while offset < segment.words.count {
                let start =
                    if offset == 0 { segment.start }
                    else { segment.words[offset].start }
                var next = offset
                var sentence: Int?
                var end = start
                while next < segment.words.count, max(end, segment.words[next].end) - start <= limit {
                    end = max(end, segment.words[next].end)
                    if Self.endsSentence(segment.words[next].text) == true { sentence = next + 1 }
                    next += 1
                }
                let boundary = sentence ?? max(offset + 1, next)
                let words = Array(segment.words[offset ..< boundary])
                let wordEnd = words.reduce(start) { max($0, $1.end) }
                let cueEnd =
                    if boundary == segment.words.count && segment.end - start <= limit { segment.end }
                    else { wordEnd }
                result.append(
                    MergedSegment(speaker: segment.speaker, start: start, end: cueEnd, words: words, paragraphBreak: offset == 0 && segment.paragraphBreak, overlap: segment.overlap))
                offset = boundary
            }
            return result
        }
        return MergedSegment.chronological(cues)
    }

    private static func endsSentence(_ text: String) -> Bool {
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]} ")).last.map { ".!?。！？".contains($0) } ?? false
    }
}
