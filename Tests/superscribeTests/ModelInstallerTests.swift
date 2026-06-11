import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ModelInstaller", .serialized, ResetSharedStateTrait())
struct ModelInstallerTests {

    private func tempDir() throws -> URL {
        try TestHelpers.makeTempDir(prefix: "superscribe-installer-tests")
    }

    private func makeMlmodelc(at dir: URL) throws {
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Encoder.mlmodelc"),
            withIntermediateDirectories: true
        )
    }

    @Test func isInstalledRecognisesMlmodelcDir() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Parakeet: directory with .mlmodelc bundle.
        let parakeetModel = dir.appendingPathComponent("parakeet-v3", isDirectory: true)
        try FileManager.default.createDirectory(at: parakeetModel, withIntermediateDirectories: true)
        #expect(await ModelInstaller.isInstalled(at: parakeetModel, backend: .parakeet) == false)
        try makeMlmodelc(at: parakeetModel)
        #expect(await ModelInstaller.isInstalled(at: parakeetModel, backend: .parakeet) == true)
    }

    @Test func isInstalledWhisperRequiresBinFile() async throws {
        let dir = try tempDir()
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

    @Test func preflightDiskSpacePassesWhenSizeUnknown() throws {
        let dir = try tempDir()
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

    @Test func removeInstalledWhisperDeletesBinAndEncoderBundle() async throws {
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

    @Test func preflightDiskSpaceRejectsImpossiblyLargeRequest() throws {
        let dir = try tempDir()
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

@Suite("Backend installPath conventions", .serialized, ResetSharedStateTrait())
struct InstallPathTests {

    @Test func whisperInstallPathUsesBinCacheConvention() {
        let path = WhisperBackend.installPath(for: "large-v3-turbo")
        #expect(path.lastPathComponent == "large-v3-turbo.bin")
        #expect(path.path.contains("superscribe/whisper/large-v3-turbo.bin"))
    }

    @Test func parakeetInstallPathMatchesFluidAudioConvention() {
        let path = ParakeetBackend.installPath(for: "v3")
        #expect(path.lastPathComponent == "parakeet-tdt-0.6b-v3")
        #expect(path.path.contains("FluidAudio/Models/parakeet-tdt-0.6b-v3"))
    }

    @Test func parakeetInstallPathPassesUnknownIdsThrough() {
        let path = ParakeetBackend.installPath(for: "parakeet-future-coreml")
        #expect(path.lastPathComponent == "parakeet-future-coreml")
    }

    @Test func parakeetRepoFolderNameRoundTrips() {
        #expect(ParakeetBackend.installFolderName(for: "v3") == "parakeet-tdt-0.6b-v3")
        #expect(ParakeetBackend.installFolderName(for: "tdt-ja") == "parakeet-ja")
        #expect(ParakeetBackend.installFolderName(for: "unknown-id") == "unknown-id")
    }

    @Test func parakeetHfRepoIdResolvesShortIds() {
        #expect(
            ParakeetBackend.huggingFaceRepoId(for: "v3")
                == "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        )
        #expect(
            ParakeetBackend.huggingFaceRepoId(for: "tdt-ja")
                == "FluidInference/parakeet-0.6b-ja-coreml"
        )
    }
}

@Suite("ModelInstallationError", .serialized, ResetSharedStateTrait())
struct ModelInstallationErrorTests {

    @Test func modelNotInstalledMessageNamesInstallCommand() {
        let err = ModelInstallationError.modelNotInstalled(model: "tiny", backend: .whisperCpp)
        let msg = err.description
        #expect(msg.contains("Whisper"))
        #expect(msg.contains("tiny"))
        #expect(msg.contains("superscribe models --download tiny --backend whisper"))
    }

    @Test func unknownModelListsAvailable() {
        let err = ModelInstallationError.unknownModel(
            model: "bogus", backend: .parakeet, available: ["v2", "v3"]
        )
        let msg = err.description
        #expect(msg.contains("bogus"))
        #expect(msg.contains("v2, v3"))
    }

    @Test func unknownModelEmptyCatalogMessage() {
        let err = ModelInstallationError.unknownModel(
            model: "missing", backend: .whisperCpp, available: []
        )
        #expect(err.description.contains("(catalog empty)") == true)
    }

    @Test func installLockEarlyReturnAfterFire() async {
        await ModelInstaller.exerciseInstallLockEarlyReturnForTesting()
    }
}
