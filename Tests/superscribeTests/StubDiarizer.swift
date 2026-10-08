import Foundation

@testable import SuperscribeKit

/// Returns fixed speaker activity regardless of the audio.
struct StubDiarizer: Diarizer {
    let activity: SpeakerActivity

    /// - Parameters:
    ///   - slots: The active speaker slot per 10 ms frame; `nil` is silence.
    ///   - speakerCount: Speaker slots per frame.
    /// - Throws: `InputValidationError` for an invalid activity shape.
    init(slots: [Int?], speakerCount: Int = 2) throws {
        let probabilities = slots.flatMap { slot in
            return (0 ..< speakerCount).map { index -> Float in
                if index == slot { return 0.9 }
                return 0.1
            }
        }
        self.activity = try SpeakerActivity(probabilities: probabilities, speakerCount: speakerCount, frameDuration: 0.01)
    }

    func speakerActivity(in audio: PreparedAudio) async throws -> SpeakerActivity {
        return self.activity
    }
}
