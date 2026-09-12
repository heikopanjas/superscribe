import Foundation

/// A speaker track to be transcribed: a human-readable name and the path
/// to its audio file.
public struct TrackInput: Sendable {
    public let speaker: String
    public let file: URL

    public init(speaker: String, file: URL) {
        self.speaker = speaker
        self.file = file
    }
}
