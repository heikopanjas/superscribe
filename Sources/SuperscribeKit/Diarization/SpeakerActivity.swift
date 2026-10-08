import Foundation

/// Frame-level speaker probabilities produced by a `Diarizer`.
public struct SpeakerActivity: Sendable, Hashable {
    /// Row-major `[frame][speaker]` probabilities in `0 ... 1`.
    public let probabilities: [Float]
    /// Number of speaker slots per frame.
    public let speakerCount: Int
    /// Duration covered by one frame.
    public let frameDuration: TimeInterval

    /// - Throws: `InputValidationError` when the shape or frame duration is invalid.
    public init(probabilities: [Float], speakerCount: Int, frameDuration: TimeInterval) throws {
        guard speakerCount > 0, frameDuration.isFinite == true, frameDuration > 0, probabilities.count % speakerCount == 0 else {
            throw InputValidationError("Speaker activity needs a positive speaker count and frame duration and whole frames")
        }
        self.probabilities = probabilities
        self.speakerCount = speakerCount
        self.frameDuration = frameDuration
    }

    public var frameCount: Int { return self.probabilities.count / self.speakerCount }
}
