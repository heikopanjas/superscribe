import Foundation

/// A contiguous span of speech detected in a single audio track.
public struct SpeechSegment: Codable, Sendable, Hashable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { return self.end - self.start }
}
