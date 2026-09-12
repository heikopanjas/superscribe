import Foundation

public struct MergedTranscriptDocument: Codable, Sendable {
    public let version: Int
    public let segments: [Segment]

    public struct Segment: Codable, Sendable {
        public let speaker: String
        public let start: TimeInterval
        public let end: TimeInterval
        public let text: String
        public let paragraphBreak: Bool
        public let overlap: Bool
        public let words: [TimedWord]
    }

    internal init(segments: [MergedSegment]) {
        self.version = 1
        self.segments = segments.map {
            Segment(
                speaker: $0.speaker, start: $0.start, end: $0.end, text: $0.words.map(\.text).joined(separator: " "), paragraphBreak: $0.paragraphBreak, overlap: $0.overlap,
                words: $0.words)
        }
    }
}
