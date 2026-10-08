import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Speaker turn builder", .serialized, ResetSharedStateTrait())
struct SpeakerTurnBuilderTests {
    private static let exact = AnalyzerConfig(minSilenceDuration: 0, padding: 0, minSegmentDuration: 0)

    private func speakers(_ slots: [Int?], speakerCount: Int = 2, duration: TimeInterval? = nil, config: AnalyzerConfig = Self.exact) throws -> [[SpeechSegment]] {
        let activity = try StubDiarizer(slots: slots, speakerCount: speakerCount).activity
        return SpeakerTurnBuilder.speakers(from: activity, duration: duration ?? Double(slots.count) * 0.01, config: config)
    }

    private func expectSegments(_ actual: [SpeechSegment], _ expected: [(TimeInterval, TimeInterval)], sourceLocation: SourceLocation = #_sourceLocation) -> Void {
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        for (segment, bounds) in zip(actual, expected) {
            #expect(abs(segment.start - bounds.0) < 1e-9, sourceLocation: sourceLocation)
            #expect(abs(segment.end - bounds.1) < 1e-9, sourceLocation: sourceLocation)
        }
    }

    @Test func emptyActivityHasNoSpeakers() throws -> Void {
        #expect(try self.speakers([]).isEmpty == true)
    }

    @Test func paddingIsClampedToRecordingBounds() throws -> Void {
        let slots: [Int?] = Array(repeating: nil, count: 10) + Array(repeating: 0, count: 50) + Array(repeating: nil, count: 10)
        let speakers = try self.speakers(slots, config: AnalyzerConfig())
        try #require(speakers.count == 1)
        self.expectSegments(speakers[0], [(0, 0.7)])
    }

    @Test func speakersAreOrderedByFirstAppearance() throws -> Void {
        let slots: [Int?] = Array(repeating: 2, count: 20) + Array(repeating: 0, count: 20)
        let speakers = try self.speakers(slots, speakerCount: 3)
        try #require(speakers.count == 2)
        self.expectSegments(speakers[0], [(0, 0.2)])
        self.expectSegments(speakers[1], [(0.2, 0.4)])
    }

    @Test func overlappingSpeechGoesToTheLikeliestSlotAndThresholdIsInclusive() throws -> Void {
        let frames: [[Float]] =
            Array(repeating: [0.5, 0.5], count: 10) + Array(repeating: [0.49, 0.2], count: 10) + Array(repeating: [0.8, 0.9], count: 10)
        let activity = try SpeakerActivity(probabilities: frames.flatMap { $0 }, speakerCount: 2, frameDuration: 0.01)
        let speakers = SpeakerTurnBuilder.speakers(from: activity, duration: 0.3, config: Self.exact)
        try #require(speakers.count == 2)
        self.expectSegments(speakers[0], [(0, 0.1)])
        self.expectSegments(speakers[1], [(0.2, 0.3)])
    }

    @Test func shortSilenceMergesOnlyWithinTheSameSpeaker() throws -> Void {
        let slots: [Int?] =
            Array(repeating: 0, count: 10) + Array(repeating: nil, count: 3) + Array(repeating: 0, count: 10) + Array(repeating: 1, count: 10)
            + Array(repeating: 0, count: 10)
        let speakers = try self.speakers(slots, config: AnalyzerConfig(minSilenceDuration: 0.05, padding: 0, minSegmentDuration: 0))
        try #require(speakers.count == 2)
        self.expectSegments(speakers[0], [(0, 0.23), (0.33, 0.43)])
        self.expectSegments(speakers[1], [(0.23, 0.33)])
    }

    @Test func paddingStopsHalfwayToTheNeighboringTurn() throws -> Void {
        let slots: [Int?] = Array(repeating: 0, count: 10) + Array(repeating: nil, count: 4) + Array(repeating: 1, count: 10)
        let speakers = try self.speakers(slots, config: AnalyzerConfig(minSilenceDuration: 0, padding: 0.15, minSegmentDuration: 0))
        try #require(speakers.count == 2)
        self.expectSegments(speakers[0], [(0, 0.12)])
        self.expectSegments(speakers[1], [(0.12, 0.24)])
    }

    @Test func shortTurnsAndTheirSpeakersAreDropped() throws -> Void {
        let slots: [Int?] = Array(repeating: 0, count: 30) + Array(repeating: 1, count: 2)
        let speakers = try self.speakers(slots, config: AnalyzerConfig(minSilenceDuration: 0, padding: 0, minSegmentDuration: 0.1))
        try #require(speakers.count == 1)
        self.expectSegments(speakers[0], [(0, 0.3)])
    }

    @Test func framesBeyondTheRecordingAreClamped() throws -> Void {
        let slots: [Int?] = Array(repeating: 0, count: 5) + Array(repeating: nil, count: 10) + Array(repeating: 0, count: 5)
        let speakers = try self.speakers(slots, speakerCount: 1, duration: 0.1, config: AnalyzerConfig(minSilenceDuration: 0, padding: 0, minSegmentDuration: 0.01))
        try #require(speakers.count == 1)
        self.expectSegments(speakers[0], [(0, 0.05)])
    }
}
