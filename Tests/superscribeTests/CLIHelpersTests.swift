import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("CLI helpers", .serialized, ResetSharedStateTrait())
struct CLIHelpersTests {
    @Test func defaultIntermediateOutputPathUsesBackendWhenEmpty() -> Void {
        let path = defaultIntermediateOutputPath(backend: .whisperCpp, explicitOutput: "")
        #expect(path == "transcript.superscribe.whisper.cpp.json")
    }

    @Test func defaultIntermediateOutputPathHonorsExplicit() -> Void {
        let path = defaultIntermediateOutputPath(backend: .parakeet, explicitOutput: "custom.json")
        #expect(path == "custom.json")
    }

    @Test func saveIntermediateTranscriptWritesJSON() throws -> Void {
        let transcript = IntermediateTranscript(
            session: nil,
            tracks: [],
            metadata: IntermediateTranscript.Metadata(
                backend: .parakeet,
                model: "v3",
                language: "en",
                analyzer: IntermediateTranscript.AnalyzerSettings(
                    silenceThresholdDB: -40,
                    minSilence: 0.5,
                    padding: 0.15
                )
            )
        )
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("out-\(UUID().uuidString).json")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }

        try saveIntermediateTranscript(transcript, to: path)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try IntermediateTranscript.jsonDecoder().decode(IntermediateTranscript.self, from: data)
        #expect(decoded.metadata.model == "v3")
        #expect(decoded.metadata.backend == .parakeet)
    }

    @Test func formatBytesDelegatesToKit() -> Void {
        #expect(formatBytes(1024) == ByteFormatting.format(1024))
    }
}
