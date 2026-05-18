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

        let model = dir.appendingPathComponent("openai_whisper-tiny", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        #expect(!ModelInstaller.isInstalled(at: model, backend: .whisper))

        try makeMlmodelc(at: model)
        #expect(ModelInstaller.isInstalled(at: model, backend: .whisper))
        #expect(ModelInstaller.isInstalled(at: model, backend: .parakeet))
    }

    @Test func isInstalledRejectsMissingDir() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("not-there", isDirectory: true)
        #expect(!ModelInstaller.isInstalled(at: missing, backend: .whisper))
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

    @Test func whisperInstallPathMatchesWhisperKitConvention() {
        let path = WhisperBackend.installPath(for: "tiny")
        #expect(path.lastPathComponent == "openai_whisper-tiny")
        #expect(
            path.path.hasSuffix(
                "Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny"
            ))
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
        let err = ModelInstallationError.modelNotInstalled(model: "tiny", backend: .whisper)
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
