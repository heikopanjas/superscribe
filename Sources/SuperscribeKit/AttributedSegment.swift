import Foundation

// MARK: - Merge pipeline types

/// A speech segment annotated with its speaker.
public struct AttributedSegment: Sendable, Hashable {
    public let speaker: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let words: [TimedWord]

    public init(speaker: String, start: TimeInterval, end: TimeInterval, words: [TimedWord]) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.words = words
    }
}
