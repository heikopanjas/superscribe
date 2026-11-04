import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Diarization pipeline", .serialized, ResetSharedStateTrait())
struct DiarizationPipelineTests {
    /// Slot 1 speaks the first second, slot 0 the second.
    private static func diarizer() throws -> StubDiarizer {
        return try StubDiarizer(slots: Array(repeating: 1, count: 100) + Array(repeating: 0, count: 100))
    }

    private func run(_ tracks: [TrackInput], diarizer: (any Diarizer)?) async throws -> IntermediateTranscript {
        let config = PipelineConfig(tracks: tracks, transcriptionConfig: TranscriptionConfig(language: "en", prompt: nil), diarizer: diarizer)
        return try await TranscribePipeline(transcriber: MockTranscriber(), config: config).run()
    }

    @Test func diarizedSpeakersBecomeNamedTracksInAppearanceOrder() async throws -> Void {
        let url = try TestHelpers.makeTemp16kMonoFloatWAV(name: "panel", durationSeconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let transcript = try await self.run([TrackInput(speaker: "panel", file: url, diarization: TrackDiarization(speakerNames: ["Alice"]))], diarizer: try Self.diarizer())
        #expect(transcript.tracks.map(\.speaker) == ["Alice", "Speaker 1"])
        #expect(transcript.tracks.allSatisfy { $0.file == url.path } == true)
        let alice = try #require(transcript.tracks.first?.segments.first)
        #expect(alice.start == 0)
        #expect(abs(alice.end - 1) < 1e-9)
    }

    @Test func unnamedSpeakersAreNumberedAcrossMixedTracks() async throws -> Void {
        let host = try TestHelpers.makeTemp16kMonoFloatWAV(name: "host", durationSeconds: 2)
        let first = try TestHelpers.makeTemp16kMonoFloatWAV(name: "first", durationSeconds: 2)
        let second = try TestHelpers.makeTemp16kMonoFloatWAV(name: "second", durationSeconds: 2)
        defer { for url in [host, first, second] { try? FileManager.default.removeItem(at: url) } }
        let transcript = try await self.run(
            [
                TrackInput(speaker: "Host", file: host), TrackInput(speaker: "first", file: first, diarization: TrackDiarization()),
                TrackInput(speaker: "second", file: second, diarization: TrackDiarization())
            ], diarizer: try Self.diarizer())
        #expect(transcript.tracks.map(\.speaker) == ["Host", "Speaker 1", "Speaker 2", "Speaker 3", "Speaker 4"])
    }

    @Test func mixedTracksRequireADiarizer() async throws -> Void {
        let url = try TestHelpers.makeTemp16kMonoFloatWAV(name: "nodiarizer", durationSeconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: InputValidationError.self) {
            _ = try await self.run([TrackInput(speaker: "panel", file: url, diarization: TrackDiarization())], diarizer: nil)
        }
    }

    @Test func blankDiarizedNamesAreRejected() async throws -> Void {
        let url = try TestHelpers.makeTemp16kMonoFloatWAV(name: "blank", durationSeconds: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: InputValidationError.self) {
            _ = try await self.run([TrackInput(speaker: "panel", file: url, diarization: TrackDiarization(speakerNames: ["Alice", " "]))], diarizer: try Self.diarizer())
        }
    }
}
