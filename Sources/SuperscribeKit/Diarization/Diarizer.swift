import Foundation

/// Estimates who speaks when in a mixed recording.
public protocol Diarizer: Sendable {
    /// Speaker probabilities for the whole prepared recording, with slots numbered consistently across the file.
    func speakerActivity(in audio: PreparedAudio) async throws -> SpeakerActivity
}
