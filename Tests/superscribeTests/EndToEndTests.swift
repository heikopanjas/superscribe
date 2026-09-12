import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - End-to-end merge test

@Suite("EndToEnd", .serialized, ResetSharedStateTrait())
struct EndToEndTests {
    @Test("pipeline + merger produces VTT with both speakers")
    func pipelineToVTT() async throws -> Void {
        let aliceURL = try TestHelpers.makeTempSineWAV(name: "Alice", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: aliceURL) }
        let bobURL = try TestHelpers.makeTempSineWAV(name: "Bob", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: bobURL) }

        let transcript = try await TestHelpers.runMockPipeline(tracks: [
            TrackInput(speaker: "Alice", file: aliceURL),
            TrackInput(speaker: "Bob", file: bobURL)
        ])

        let merger = Merger()
        let merged = try merger.merge(transcript)
        let vtt = try VTTFormatter(includeWords: false).render(merged)

        #expect(vtt.hasPrefix("WEBVTT\n"))
        #expect(vtt.contains("<v Alice>"))
        #expect(vtt.contains("<v Bob>"))
    }
}
