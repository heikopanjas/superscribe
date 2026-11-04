import Foundation

/// Marks a track as a mixed recording whose speakers are separated by a `Diarizer`.
public struct TrackDiarization: Sendable, Hashable {
    /// Names for diarized speakers in order of first appearance; unnamed speakers become `Speaker N`.
    public let speakerNames: [String]

    public init(speakerNames: [String] = []) {
        self.speakerNames = speakerNames
    }
}
