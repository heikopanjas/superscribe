import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("CLI validation before setup", .serialized, ResetSharedStateTrait())
struct CLIValidationTests {
    @Test func mappingRoundTripsOutsideWorkingDirectoryAndIgnoresDirectories() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let elsewhere = root.appendingPathComponent("elsewhere")
            let cwd = root.appendingPathComponent("cwd")
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
            let file = elsewhere.appendingPathComponent("speaker.wav")
            try Data([0]).write(to: file)
            try FileManager.default.createDirectory(at: elsewhere.appendingPathComponent("directory.wav"), withIntermediateDirectories: true)
            let mapping = try TrackInputScanning.scanTracks(in: elsewhere, relativeTo: cwd)
            #expect(mapping.count == 1)
            let mappingURL = cwd.appendingPathComponent("tracks.json")
            try JSONEncoder().encode(mapping).write(to: mappingURL)
            #expect(try TrackMappingLoader.load(from: mappingURL, relativeTo: cwd).first?.file == file)
            try JSONEncoder().encode(["Speaker": "../elsewhere/speaker.wav"]).write(to: mappingURL)
            #expect(try TrackMappingLoader.load(from: mappingURL, relativeTo: cwd).first?.file.standardizedFileURL == file)
        }
    }

    @Test func invalidOptionsAreRejected() -> Void {
        for arguments in [["--list", "--capabilities"], ["--set-default", "parakeet", "--list"]] {
            #expect(throws: (any Error).self) { _ = try BackendCommand.parse(arguments) }
        }
        for arguments in [["--yes"], ["--set-default", "v3", "--refresh"], ["--refresh", "--json"], ["--refresh", "--list"]] {
            #expect(throws: (any Error).self) { _ = try ModelCommand.parse(arguments) }
        }
        for arguments in [["--padding", "nan"], ["--min-silence", "-1"], ["--silence-threshold", "inf"]] {
            #expect(throws: (any Error).self) { _ = try TranscribeOptions.parse(arguments) }
        }
        #expect(throws: InputValidationError.self) { try TrackInput.validate([]) }
        #expect(throws: InputValidationError.self) { try TrackInput(speaker: " \n", file: URL(fileURLWithPath: "/missing")).validate() }
        #expect(throws: InputValidationError.self) { try TrackInput(speaker: "A", file: FileManager.default.temporaryDirectory).validate() }
        #expect(throws: InputValidationError.self) { try AnalyzerConfig(windowSize: 0).validate() }
        #expect(throws: InputValidationError.self) { try TranscriptionConfig(language: "en\0", prompt: nil).validate() }
        #expect(throws: InputValidationError.self) { try TranscriptionConfig(prompt: "hint\0").validate() }
    }
}
