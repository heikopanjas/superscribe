import Foundation

// MARK: - Speech & transcription primitives

/// A single recognised word with its time interval inside the source audio.
public struct TimedWord: Codable, Sendable, Hashable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}
