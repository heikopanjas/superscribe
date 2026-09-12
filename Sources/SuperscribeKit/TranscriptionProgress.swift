import Foundation

/// Progress update emitted after each segment is transcribed.
public struct TranscriptionProgress: Sendable {
    /// Speaker name of the current track.
    public let speaker: String
    /// 1-based index of the completed segment within the track.
    public let segmentIndex: Int
    /// Total segments in the current track.
    public let totalSegments: Int
    /// Running total of completed segments across all tracks.
    public let overallCompleted: Int
    /// Total segments across all tracks.
    public let overallTotal: Int
}
