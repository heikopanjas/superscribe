import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Analyzer

@Suite("Analyzer URL I/O", .serialized, ResetSharedStateTrait())
struct AnalyzerURLTests {
    @Test func errorDescriptions() throws -> Void {
        let url = URL(fileURLWithPath: "/tmp/missing.wav")
        #expect(AnalyzerError.unsupportedFormat(url).description.contains("Unsupported") == true)
        let read = AnalyzerError.readFailed(url, underlying: URLError(.fileDoesNotExist))
        #expect(read.description.contains("missing.wav") == true)
    }

    @Test func detectSpeechFromURL() throws -> Void {
        let wav = try TestHelpers.makeTempSineWAV(name: "analyzer-url", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: wav) }
        let analyzer = Analyzer(config: AnalyzerConfig(padding: 0))
        let segments = try analyzer.detectSpeech(in: wav)
        #expect(segments.isEmpty == false)
    }

    @Test func detectSpeechFromStereoURL() throws -> Void {
        let wav = try TestHelpers.makeTempSineWAV(
            name: "analyzer-stereo",
            durationSeconds: 0.5,
            sampleRate: 48_000,
            channels: 2
        )
        defer { try? FileManager.default.removeItem(at: wav) }
        let segments = try Analyzer().detectSpeech(in: wav)
        #expect(segments.isEmpty == false)
    }

    @Test func readMonoFloat32MissingFileThrows() throws -> Void {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).wav")
        #expect(throws: AnalyzerError.self) {
            _ = try Analyzer.readMonoFloat32(from: url)
        }
    }

    @Test func readMonoFloat32RejectsNonAudioFile() throws -> Void {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-audio-\(UUID().uuidString).txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: AnalyzerError.self) {
            _ = try Analyzer.readMonoFloat32(from: url)
        }
    }
}
