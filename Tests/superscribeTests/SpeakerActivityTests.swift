import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Speaker activity", .serialized, ResetSharedStateTrait())
struct SpeakerActivityTests {
    @Test func frameCountDividesBySpeakers() throws -> Void {
        let activity = try SpeakerActivity(probabilities: [0, 1, 1, 0, 0.5, 0.5], speakerCount: 2, frameDuration: 0.01)
        #expect(activity.frameCount == 3)
    }

    @Test(arguments: [(2, 0.01, 3), (0, 0.01, 0), (2, 0, 2), (2, Double.infinity, 2)])
    func invalidShapesAreRejected(speakerCount: Int, frameDuration: TimeInterval, values: Int) throws -> Void {
        #expect(throws: InputValidationError.self) {
            _ = try SpeakerActivity(probabilities: Array(repeating: 0, count: values), speakerCount: speakerCount, frameDuration: frameDuration)
        }
    }
}
