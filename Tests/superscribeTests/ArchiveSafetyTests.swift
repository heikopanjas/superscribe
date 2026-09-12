import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Archive confinement", .serialized, ResetSharedStateTrait())
struct ArchiveSafetyTests {
    @Test(arguments: ["../escape", "/absolute", "directory/../../escape", "bad\\path"])
    func rejectsTraversalBeforeExtraction(name: String) async throws -> Void {
        try await TestHelpers.withTempDirectory { root in
            let archive = root.appendingPathComponent("input.zip")
            let destination = root.appendingPathComponent("output")
            try ZIPFixture.archive([.init(name: name, data: Data([1]))]).write(to: archive)
            await #expect(throws: (any Error).self) { try await WhisperEncoderInstaller.unzipArchive(at: archive, into: destination) }
            #expect(FileManager.default.fileExists(atPath: destination.path) == false)
        }
    }

    @Test func rejectsSymlinksAndReportsExtractionFailure() async throws -> Void {
        try await TestHelpers.withTempDirectory { root in
            let archive = root.appendingPathComponent("input.zip")
            let destination = root.appendingPathComponent("output")
            try ZIPFixture.archive([.init(name: "link", data: Data("/tmp".utf8), mode: 0o120777)]).write(to: archive)
            await #expect(throws: ModelInstallationError.self) { try await WhisperEncoderInstaller.unzipArchive(at: archive, into: destination) }
            try ZIPFixture.archive([.init(name: "model/data", data: Data([1]))]).write(to: archive)
            try Data([1]).write(to: destination)
            await #expect(throws: ModelInstallationError.self) { try await WhisperEncoderInstaller.unzipArchive(at: archive, into: destination) }
        }
    }
}
