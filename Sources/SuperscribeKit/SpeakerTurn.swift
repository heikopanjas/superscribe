import Foundation

/// A speech run attributed to one speaker slot on a shared, exclusive timeline.
internal struct SpeakerTurn: Sendable, Hashable {
    internal let speakerIndex: Int
    internal let segment: SpeechSegment
}
