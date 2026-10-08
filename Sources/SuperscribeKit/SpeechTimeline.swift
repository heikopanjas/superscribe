import Foundation

/// Shared post-processing for time-ordered, non-overlapping speech runs.
internal enum SpeechTimeline {
    /// Merges same-speaker runs separated by less than the minimum silence, pads each run into at most half of
    /// the adjacent silence (so padding never crosses into a neighboring run), and drops runs shorter than the
    /// minimum segment duration.
    internal static func finalize(_ turns: [SpeakerTurn], duration: TimeInterval, config: AnalyzerConfig) -> [SpeakerTurn] {
        var merged: [SpeakerTurn] = []
        merged.reserveCapacity(turns.count)
        for turn in turns {
            if let last = merged.last {
                if last.speakerIndex == turn.speakerIndex {
                    if turn.segment.start - last.segment.end < config.minSilenceDuration {
                        merged[merged.count - 1] = SpeakerTurn(speakerIndex: last.speakerIndex, segment: SpeechSegment(start: last.segment.start, end: turn.segment.end))
                        continue
                    }
                }
            }
            merged.append(turn)
        }
        return merged.indices.compactMap { index in
            let segment = merged[index].segment
            let lowerBound: TimeInterval =
                if index > 0 { (merged[index - 1].segment.end + segment.start) / 2 }
                else { 0 }
            let upperBound: TimeInterval =
                if index < merged.count - 1 { (segment.end + merged[index + 1].segment.start) / 2 }
                else { duration }
            let padded = SpeechSegment(start: max(lowerBound, segment.start - config.padding), end: min(upperBound, segment.end + config.padding))
            if padded.duration < config.minSegmentDuration { return nil }
            return SpeakerTurn(speakerIndex: merged[index].speakerIndex, segment: padded)
        }
    }
}
