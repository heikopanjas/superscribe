import Foundation

/// Converts frame-level speaker probabilities into per-speaker speech segments.
internal enum SpeakerTurnBuilder {
    /// Minimum probability for a frame to count as speech.
    internal static let threshold: Float = 0.5

    /// Assigns each frame to its most likely speaker at or above the threshold (ties pick the lower slot), so
    /// overlapping speech in the shared recording is transcribed once. Returns segments grouped by speaker in order
    /// of first appearance.
    internal static func speakers(from activity: SpeakerActivity, duration: TimeInterval, config: AnalyzerConfig) -> [[SpeechSegment]] {
        var runs: [SpeakerTurn] = []
        var current: (speaker: Int, start: Int)?
        for frame in 0 ... activity.frameCount {
            let speaker =
                if frame < activity.frameCount { Self.speaker(at: frame, in: activity) }
                else { -1 }
            if let run = current {
                if run.speaker == speaker { continue }
                let segment = SpeechSegment(start: min(duration, Double(run.start) * activity.frameDuration), end: min(duration, Double(frame) * activity.frameDuration))
                runs.append(SpeakerTurn(speakerIndex: run.speaker, segment: segment))
                current = nil
            }
            if speaker >= 0 { current = (speaker, frame) }
        }
        var slots: [Int: Int] = [:]
        var speakers: [[SpeechSegment]] = []
        for turn in SpeechTimeline.finalize(runs, duration: duration, config: config) {
            let slot = slots[turn.speakerIndex] ?? speakers.count
            if slot == speakers.count {
                slots[turn.speakerIndex] = slot
                speakers.append([])
            }
            speakers[slot].append(turn.segment)
        }
        return speakers
    }

    private static func speaker(at frame: Int, in activity: SpeakerActivity) -> Int {
        let row = frame * activity.speakerCount
        var speaker = 0
        var highest = activity.probabilities[row]
        for index in 1 ..< activity.speakerCount where activity.probabilities[row + index] > highest {
            speaker = index
            highest = activity.probabilities[row + index]
        }
        if highest >= Self.threshold { return speaker }
        return -1
    }
}
