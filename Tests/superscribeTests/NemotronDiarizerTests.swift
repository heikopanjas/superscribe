import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Nemotron diarizer", .serialized, ResetSharedStateTrait())
struct NemotronDiarizerTests {
    private func preparedAudio(seconds: Double, sampleRate: Int = 16_000) throws -> PreparedAudio {
        let url = try TestHelpers.makeTempSineWAV(name: "mixed", durationSeconds: seconds, sampleRate: Double(sampleRate), channels: 1, amplitude: 0.25)
        return try PreparedAudio(url: url, format: AudioFormat(sampleRate: sampleRate, channels: 1), temporary: true)
    }

    @Test func streamsWindowsThatTileTheRecording() async throws -> Void {
        let session = StubDiarizationSession()
        NemotronDiarizer.openSession = { _ in return session }
        let audio = try self.preparedAudio(seconds: 65)
        let activity = try await NemotronDiarizer(modelDirectory: URL(fileURLWithPath: "/unused")).speakerActivity(in: audio)
        #expect(session.appendedWindows == [480_000, 480_000, 80_000])
        #expect(activity.probabilities == [1, 0, 1, 0, 1, 0, 0, 1])
        #expect(activity.speakerCount == 2)
        #expect(activity.frameDuration == 0.01)
    }

    @Test func passesTheModelDirectoryToTheSession() async throws -> Void {
        let directory = URL(fileURLWithPath: "/models/diarizer")
        let opened = Counter()
        NemotronDiarizer.openSession = { url in
            #expect(url == directory)
            await opened.increment()
            return StubDiarizationSession()
        }
        _ = try await NemotronDiarizer(modelDirectory: directory).speakerActivity(in: try self.preparedAudio(seconds: 0.5))
        #expect(await opened.value == 1)
    }

    @Test func defaultsToTheInstalledModelPath() throws -> Void {
        _ = try NemotronDiarizer()
    }

    @Test func rejectsAudioThatIsNot16kMono() async throws -> Void {
        NemotronDiarizer.openSession = { _ in
            Issue.record("Session must not open for unsupported audio")
            return StubDiarizationSession()
        }
        let audio = try self.preparedAudio(seconds: 0.5, sampleRate: 48_000)
        await #expect(throws: AudioPreparerError.self) {
            _ = try await NemotronDiarizer(modelDirectory: URL(fileURLWithPath: "/unused")).speakerActivity(in: audio)
        }
    }

    @Test func missingCoreMLModelFailsWithoutDownloading() async throws -> Void {
        try await TestHelpers.withTempDirectory(prefix: "diarizer-missing") { directory in
            let audio = try self.preparedAudio(seconds: 0.5)
            await #expect(throws: (any Error).self) {
                _ = try await NemotronDiarizer(modelDirectory: directory).speakerActivity(in: audio)
            }
        }
    }
}
