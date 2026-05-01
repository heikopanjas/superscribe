import Foundation

/// Configuration for the merge pipeline.
public struct MergerConfig: Sendable, Hashable {
    public var overlapPolicy: OverlapPolicy
    public var gapThreshold: TimeInterval
    public var maxCueDuration: TimeInterval?
    /// Maximum gap between same-speaker segments to coalesce them.
    public var maxCoalesceGap: TimeInterval

    public init(
        overlapPolicy: OverlapPolicy = .preserve,
        gapThreshold: TimeInterval = 3.0,
        maxCueDuration: TimeInterval? = nil,
        maxCoalesceGap: TimeInterval = 1.0
    ) {
        self.overlapPolicy = overlapPolicy
        self.gapThreshold = gapThreshold
        self.maxCueDuration = maxCueDuration
        self.maxCoalesceGap = maxCoalesceGap
    }
}

/// Merges N speaker tracks into a single chronological transcript.
public struct Merger: Sendable {
    public let config: MergerConfig

    public init(config: MergerConfig = MergerConfig()) {
        self.config = config
    }

    public func merge(_ transcript: IntermediateTranscript) -> [MergedSegment] {
        let flat = Self.flatten(transcript.tracks)
        let resolved = resolveOverlaps(flat)
        let withBreaks = Self.insertBreaks(resolved, gapThreshold: config.gapThreshold)
        return Self.coalesce(
            withBreaks,
            maxCueDuration: config.maxCueDuration,
            maxGap: config.maxCoalesceGap
        )
    }

    // MARK: - Steps

    static func flatten(_ tracks: [IntermediateTranscript.Track]) -> [AttributedSegment] {
        tracks.flatMap { track in
            track.segments.map {
                AttributedSegment(
                    speaker: track.speaker,
                    start: $0.start,
                    end: $0.end,
                    words: $0.words
                )
            }
        }
        .sorted { $0.start < $1.start }
    }

    private func resolveOverlaps(_ segments: [AttributedSegment]) -> [AttributedSegment] {
        switch config.overlapPolicy {
            case .preserve:
                return segments
            case .trim, .interleave:
                // TODO: implement non-preserve overlap policies for non-VTT outputs.
                fatalError("OverlapPolicy.\(config.overlapPolicy.rawValue) is not implemented yet")
        }
    }

    static func insertBreaks(
        _ segments: [AttributedSegment],
        gapThreshold: TimeInterval
    ) -> [MergedSegment] {
        var previousEnd: TimeInterval = 0
        return segments.enumerated().map { index, segment in
            let gap = index == 0 ? 0 : segment.start - previousEnd
            previousEnd = max(previousEnd, segment.end)
            return MergedSegment(
                speaker: segment.speaker,
                start: segment.start,
                end: segment.end,
                words: segment.words,
                paragraphBreak: gap >= gapThreshold
            )
        }
    }

    static func coalesce(
        _ segments: [MergedSegment],
        maxCueDuration: TimeInterval?,
        maxGap: TimeInterval
    ) -> [MergedSegment] {
        var result: [MergedSegment] = []
        for segment in segments {
            guard let last = result.last,
                last.speaker == segment.speaker,
                !segment.paragraphBreak,
                segment.start - last.end < maxGap
            else {
                result.append(segment)
                continue
            }

            var merged = last
            merged.words.append(contentsOf: segment.words)
            merged.end = segment.end

            if let maxCueDuration, merged.end - merged.start > maxCueDuration {
                result.append(segment)
            }
            else {
                result[result.count - 1] = merged
            }
        }
        return result
    }
}
