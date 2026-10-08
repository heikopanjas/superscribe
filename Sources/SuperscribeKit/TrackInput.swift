import Foundation

/// A track to be transcribed: a human-readable name and the path to its audio file.
/// Mixed tracks carry `diarization` and are split into one speaker per diarized voice.
public struct TrackInput: Sendable {
    public let speaker: String
    public let file: URL
    public let diarization: TrackDiarization?

    public init(speaker: String, file: URL, diarization: TrackDiarization? = nil) {
        self.speaker = speaker
        self.file = file
        self.diarization = diarization
    }
}
