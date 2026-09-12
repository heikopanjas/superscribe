import Foundation

/// The result of transcribing a single `SpeechSegment`.
public struct SegmentTranscription: Sendable, Hashable {
    public let segment: SpeechSegment
    public let words: [TimedWord]

    public init(segment: SpeechSegment, words: [TimedWord]) {
        self.segment = segment
        self.words = words
    }
}
