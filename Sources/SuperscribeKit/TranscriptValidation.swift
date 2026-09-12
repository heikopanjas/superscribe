import Foundation

internal enum TranscriptValidation {
    internal static func interval(start: TimeInterval, end: TimeInterval) throws -> Void {
        guard start.isFinite == true, end.isFinite == true, start >= 0, end >= start,
            end < Double(Int64.max / 1000 - 1)
        else { throw InputValidationError("Transcript intervals must be finite, nonnegative, ordered, and representable in milliseconds") }
    }

    internal static func words(_ words: [TimedWord]) throws -> Void {
        var previous: TimeInterval = 0
        for word in words {
            try Self.interval(start: word.start, end: word.end)
            guard word.start >= previous else { throw InputValidationError("Words must be ordered by start time") }
            previous = word.start
        }
    }

    internal static func normalized(_ segments: [MergedSegment]) throws -> [MergedSegment] {
        return try segments.map { original in
            try Self.interval(start: original.start, end: original.end)
            try Self.words(original.words)
            var segment = original
            for word in original.words {
                segment.start = min(segment.start, word.start)
                segment.end = max(segment.end, word.end)
            }
            return segment
        }
    }
}
