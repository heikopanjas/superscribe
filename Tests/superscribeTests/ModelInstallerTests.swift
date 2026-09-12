import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ModelInstaller", .serialized, ResetSharedStateTrait())
struct ModelInstallerTests {

    private func tempDir() throws -> URL {
        return try TestHelpers.makeTempDir(prefix: "superscribe-installer-tests")
    }

    @Test func isInstalledRecognisesMlmodelcDir() async throws -> Void {
        let dir = try self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Parakeet: directory with .mlmodelc bundle.
        let parakeetModel = dir.appendingPathComponent("parakeet-v3", isDirectory: true)
        try FileManager.default.createDirectory(at: parakeetModel, withIntermediateDirectories: true)
        #expect(await ModelInstaller.isInstalled(at: parakeetModel, backend: .parakeet, modelId: "v3") == false)
        try TestHelpers.makeParakeetInstallation(at: parakeetModel)
        #expect(await ModelInstaller.isInstalled(at: parakeetModel, backend: .parakeet, modelId: "v3") == true)
    }

    @Test func isInstalledWhisperRequiresBinFile() async throws -> Void {
        let dir = try self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let binPath = dir.appendingPathComponent("large-v3-turbo.bin")
        // File absent — not installed.
        #expect(await ModelInstaller.isInstalled(at: binPath, backend: .whisperCpp) == false)
        // Create the file — now installed.
        FileManager.default.createFile(atPath: binPath.path, contents: Data("fake".utf8))
        #expect(await ModelInstaller.isInstalled(at: binPath, backend: .whisperCpp) == true)
        // A directory at that path is not a valid .bin — not installed.
        let dirPath = dir.appendingPathComponent("model-dir")
        try FileManager.default.createDirectory(at: dirPath, withIntermediateDirectories: true)
        #expect(await ModelInstaller.isInstalled(at: dirPath, backend: .whisperCpp) == false)
    }

    @Test func preflightDiskSpacePassesWhenSizeUnknown() throws -> Void {
        let dir = try self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Should not throw.
        try ModelInstaller.preflightDiskSpace(
            requiredBytes: nil,
            installPath: dir.appendingPathComponent("model")
        )
        try ModelInstaller.preflightDiskSpace(
            requiredBytes: 0,
            installPath: dir.appendingPathComponent("model")
        )
    }

    @Test func removeInstalledWhisperDeletesBinAndEncoderBundle() async throws -> Void {
        let modelId = "test-rm-\(UUID().uuidString.prefix(8))"
        let bin = WhisperBackend.installPath(for: String(modelId))
        let encoder = WhisperBackend.encoderInstallPath(for: String(modelId))
        defer {
            try? FileManager.default.removeItem(at: bin)
            try? FileManager.default.removeItem(at: encoder)
        }
        try FileManager.default.createDirectory(
            at: bin.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: bin.path, contents: Data("x".utf8))
        try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)

        let paths = try await ModelInstaller.removalPaths(modelId: String(modelId), backend: .whisperCpp)
        #expect(paths.count == 2)

        try await ModelInstaller.removeInstalled(modelId: String(modelId), backend: .whisperCpp)
        #expect(FileManager.default.fileExists(atPath: bin.path) == false)
        #expect(WhisperBackend.isEncoderInstalled(modelId: String(modelId)) == false)
    }

    @Test func preflightDiskSpaceRejectsImpossiblyLargeRequest() throws -> Void {
        let dir = try self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Far larger than any plausible volume.
        let huge: Int64 = 1_000_000_000_000_000  // 1 PB
        do {
            try ModelInstaller.preflightDiskSpace(
                requiredBytes: huge,
                installPath: dir.appendingPathComponent("model")
            )
            Issue.record("Expected insufficientDiskSpace error")
        }
        catch ModelInstallationError.insufficientDiskSpace {
            // Expected.
        }
    }
}
