import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Invalid archive diagnostics", .serialized, ResetSharedStateTrait())
struct InvalidArchiveTests {
    @Test func invalidZipCannotBeListed() async throws -> Void {
        try await TestHelpers.withTempDirectory { root in
            let file = root.appendingPathComponent("bad.zip")
            try Data("not a zip".utf8).write(to: file)
            await #expect(throws: ModelInstallationError.self) { try await WhisperEncoderInstaller.unzipArchive(at: file, into: root.appendingPathComponent("output")) }
        }
    }
}
