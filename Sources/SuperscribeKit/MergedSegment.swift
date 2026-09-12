import Foundation

/// A segment after overlap resolution, gap detection and coalescing.
public struct MergedSegment: Sendable, Hashable {
    public let speaker: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var words: [TimedWord]
    public let paragraphBreak: Bool
    public var overlap: Bool

    public init(
        speaker: String,
        start: TimeInterval,
        end: TimeInterval,
        words: [TimedWord],
        paragraphBreak: Bool,
        overlap: Bool = false
    ) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.words = words
        self.paragraphBreak = paragraphBreak
        self.overlap = overlap
    }
    internal static func chronological(_ segments: [MergedSegment]) -> [MergedSegment] {
        return segments.enumerated().sorted { lhs, rhs in
            return if lhs.element.start == rhs.element.start { lhs.offset < rhs.offset }
            else { lhs.element.start < rhs.element.start }
        }.map(\.element)
    }
}
