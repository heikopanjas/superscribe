import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ModelInstaller", .serialized)
struct ModelInstallerTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("superscribe-installer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeMlmodelc(at dir: URL) throws {
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Encoder.mlmodelc"),
            withIntermediateDirectories: true
        )
    }

    @Test func isInstalledRecognisesMlmodelcDir() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Parakeet: directory with .mlmodelc bundle.
        let parakeetModel = dir.appendingPathComponent("parakeet-v3", isDirectory: true)
        try FileManager.default.createDirectory(at: parakeetModel, withIntermediateDirectories: true)
        #expect(!ModelInstaller.isInstalled(at: parakeetModel, backend: .parakeet))
        try makeMlmodelc(at: parakeetModel)
        #expect(ModelInstaller.isInstalled(at: parakeetModel, backend: .parakeet))
    }

    @Test func isInstalledWhisperRequiresBinFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let binPath = dir.appendingPathComponent("large-v3-turbo.bin")
        // File absent — not installed.
        #expect(!ModelInstaller.isInstalled(at: binPath, backend: .whisperCpp))
        // Create the file — now installed.
        FileManager.default.createFile(atPath: binPath.path, contents: Data("fake".utf8))
        #expect(ModelInstaller.isInstalled(at: binPath, backend: .whisperCpp))
        // A directory at that path is not a valid .bin — not installed.
        let dirPath = dir.appendingPathComponent("model-dir")
        try FileManager.default.createDirectory(at: dirPath, withIntermediateDirectories: true)
        #expect(!ModelInstaller.isInstalled(at: dirPath, backend: .whisperCpp))
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

@Suite("Backend installPath conventions", .serialized)
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

@Suite("ModelInstallationError")
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
}
