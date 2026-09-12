import Foundation

/// Merges tracks in stable chronological order, retaining the origin order for tied words.
public struct Merger: Sendable {
    public let config: MergerConfig
    public init(config: MergerConfig = MergerConfig()) { self.config = config }

    public func merge(_ transcript: IntermediateTranscript) throws -> [MergedSegment] {
        guard transcript.version == IntermediateTranscript.currentVersion else { throw InputValidationError("Unsupported transcript version: \(transcript.version)") }
        try self.config.validate()
        let flat = try Self.flatten(transcript.tracks)
        let resolved: [AttributedSegment]
        switch self.config.overlapPolicy {
            case .preserve: resolved = flat
            case .trim: resolved = Self.trim(flat)
            case .interleave: resolved = Self.interleave(transcript.tracks, gapThreshold: self.config.gapThreshold)
        }
        let merged = Self.coalesce(Self.insertBreaks(resolved, gapThreshold: self.config.gapThreshold), maxCueDuration: self.config.maxCueDuration, maxGap: self.config.maxCoalesceGap)
        return try CueSplitter.split(merged, maximumDuration: self.config.maxCueDuration)
    }

    internal static func flatten(_ tracks: [IntermediateTranscript.Track]) throws -> [AttributedSegment] {
        var segments: [AttributedSegment] = []
        for track in tracks {
            guard track.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw InputValidationError("Speaker names must not be blank") }
            for segment in track.segments {
                try TranscriptValidation.interval(start: segment.start, end: segment.end)
                try TranscriptValidation.words(segment.words)
                if segment.words.isEmpty == true { continue }
                let start = segment.words.reduce(segment.start) { min($0, $1.start) }
                let end = segment.words.reduce(segment.end) { max($0, $1.end) }
                segments.append(AttributedSegment(speaker: track.speaker, start: start, end: end, words: segment.words))
            }
        }
        return segments.enumerated().sorted { lhs, rhs in
            return if lhs.element.start == rhs.element.start { lhs.offset < rhs.offset }
            else { lhs.element.start < rhs.element.start }
        }.map(\.element)
    }

    /// The first later segment from a competing speaker, computed in one reverse pass.
    private static func boundaries(_ segments: [AttributedSegment]) -> [TimeInterval?] {
        var first: AttributedSegment?
        var second: AttributedSegment?
        var result = [TimeInterval?](repeating: nil, count: segments.count)
        for index in segments.indices.reversed() {
            let segment = segments[index]
            result[index] =
                if first?.speaker == segment.speaker { second?.start }
                else { first?.start }
            if first?.speaker != segment.speaker { second = first }
            first = segment
        }
        return result
    }

    private static func trim(_ segments: [AttributedSegment]) -> [AttributedSegment] {
        let boundaries = Self.boundaries(segments)
        return segments.enumerated().compactMap { index, segment in
            guard let boundary = boundaries[index], boundary <= segment.end else { return segment }
            let end = boundary
            let words = segment.words.filter { $0.start < end }.map { TimedWord(text: $0.text, start: $0.start, end: min($0.end, end)) }
            if words.isEmpty == true { return nil }
            return AttributedSegment(speaker: segment.speaker, start: segment.start, end: end, words: words)
        }
    }

    private static func interleave(_ tracks: [IntermediateTranscript.Track], gapThreshold: TimeInterval) -> [AttributedSegment] {
        let words = tracks.flatMap { track in track.segments.flatMap { segment in segment.words.map { (track.speaker, $0) } } }
        let ordered = words.enumerated().sorted { lhs, rhs in
            return if lhs.element.1.start == rhs.element.1.start { lhs.offset < rhs.offset }
            else { lhs.element.1.start < rhs.element.1.start }
        }
        var runs: [AttributedSegment] = []
        var speaker: String?
        var run: [TimedWord] = []
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        func appendRun() -> Void {
            if let speaker { runs.append(AttributedSegment(speaker: speaker, start: start, end: end, words: run)) }
        }
        for item in ordered {
            let (name, word) = item.element
            if speaker != name || word.start - end >= gapThreshold {
                appendRun()
                speaker = name
                run = []
                start = word.start
                end = word.end
            }
            run.append(word)
            end = max(end, word.end)
        }
        appendRun()
        return runs
    }

    internal static func insertBreaks(_ segments: [AttributedSegment], gapThreshold: TimeInterval) -> [MergedSegment] {
        let next = Self.boundaries(segments)
        var previousEnd: TimeInterval = 0
        // Two greatest end times belonging to distinct speakers suffice for overlap queries.
        var longest: (String, TimeInterval)?
        var other: (String, TimeInterval)?
        return segments.enumerated().map { index, segment in
            let previousCompetingEnd =
                if longest?.0 == segment.speaker { other?.1 }
                else { longest?.1 }
            let overlap = (previousCompetingEnd ?? 0) > segment.start || (next[index] ?? .infinity) < segment.end
            let paragraph = index > 0 && segment.start - previousEnd >= gapThreshold
            previousEnd = max(previousEnd, segment.end)
            if let previous = longest, previous.0 == segment.speaker {
                longest = (segment.speaker, max(previous.1, segment.end))
            }
            else if segment.end > (longest?.1 ?? -.infinity) {
                other = longest
                longest = (segment.speaker, segment.end)
            }
            else if segment.end > (other?.1 ?? -.infinity) {
                other = (segment.speaker, segment.end)
            }
            return MergedSegment(speaker: segment.speaker, start: segment.start, end: segment.end, words: segment.words, paragraphBreak: paragraph, overlap: overlap)
        }
    }

    internal static func coalesce(_ segments: [MergedSegment], maxCueDuration: TimeInterval?, maxGap: TimeInterval) -> [MergedSegment] {
        var result: [MergedSegment] = []
        for segment in segments {
            guard let lastStart = result.last?.start, let lastEnd = result.last?.end, result.last?.speaker == segment.speaker, segment.paragraphBreak == false,
                segment.start - lastEnd < maxGap, (maxCueDuration.map({ max(lastEnd, segment.end) - lastStart <= $0 }) ?? true) == true
            else {
                result.append(segment)
                continue
            }
            result[result.count - 1].words.append(contentsOf: segment.words)
            result[result.count - 1].end = max(lastEnd, segment.end)
            result[result.count - 1].overlap = result[result.count - 1].overlap || segment.overlap
        }
        return result.map { original in
            var segment = original
            segment.words = original.words.enumerated().sorted { lhs, rhs in
                return if lhs.element.start == rhs.element.start { lhs.offset < rhs.offset }
                else { lhs.element.start < rhs.element.start }
            }.map(\.element)
            return segment
        }
    }
}
