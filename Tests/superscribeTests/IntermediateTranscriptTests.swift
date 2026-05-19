import Foundation
import Testing

@testable import SuperscribeKit

@Suite("IntermediateTranscript JSON", .serialized, ResetSharedStateTrait())
struct IntermediateTranscriptTests {

    @Test func encodesVersionSessionCreatedAndAnalyzerKeys() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let transcript = IntermediateTranscript(
            session: "/session/foo/bar",
            created: created,
            tracks: [],
            metadata: IntermediateTranscript.Metadata(
                backend: .whisperCpp,
                model: "medium",
                language: "en",
                analyzer: IntermediateTranscript.AnalyzerSettings(
                    silenceThresholdDB: -40,
                    minSilence: 0.25,
                    padding: 0.05
                )
            ),
            version: IntermediateTranscript.currentVersion
        )

        let encoder = IntermediateTranscript.jsonEncoder()
        let data = try encoder.encode(transcript)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"version\"") == true)
        #expect(json.contains("/session/foo/bar") == true)
        #expect(json.contains("silence_threshold_db") == true)
        #expect(json.contains("min_silence") == true)
        #expect(json.contains("\"padding\"") == true)

        let decoded = try IntermediateTranscript.jsonDecoder().decode(IntermediateTranscript.self, from: data)
        #expect(decoded.version == IntermediateTranscript.currentVersion)
        #expect(decoded.session == "/session/foo/bar")
        #expect(abs(decoded.created.timeIntervalSince(created)) < 0.02)
        #expect(decoded.metadata.analyzer.silenceThresholdDB == -40)
        #expect(decoded.metadata.analyzer.minSilence == 0.25)
        #expect(decoded.metadata.analyzer.padding == 0.05)
    }
}
