import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Backend installPath conventions", .serialized, ResetSharedStateTrait())
struct InstallPathTests {

    @Test func whisperInstallPathUsesBinCacheConvention() throws -> Void {
        SuperscribePaths.overrideWhisperModelCacheDirectory = nil
        let path = WhisperBackend.installPath(for: "large-v3-turbo")
        #expect(path.lastPathComponent == "large-v3-turbo.bin")
        #expect(path.path.contains("superscribe/whisper/large-v3-turbo.bin"))
    }

    @Test func parakeetInstallPathMatchesFluidAudioConvention() throws -> Void {
        SuperscribePaths.overrideFluidAudioModelsDirectory = nil
        let path = try ParakeetBackend.installPath(for: "v3")
        #expect(path.lastPathComponent == "parakeet-tdt-0.6b-v3")
        #expect(path.path.contains("FluidAudio/Models/parakeet-tdt-0.6b-v3"))
    }

    @Test func parakeetInstallPathRejectsUnknownIds() throws -> Void {
        #expect(throws: UnsupportedModelError.self) { _ = try ParakeetBackend.installPath(for: "parakeet-future-coreml") }
    }

    @Test func parakeetRepoFolderNameRoundTrips() throws -> Void {
        #expect(try ParakeetBackend.installFolderName(for: "v3") == "parakeet-tdt-0.6b-v3")
        #expect(try ParakeetBackend.installFolderName(for: "tdt-ja") == "parakeet-ja")
        #expect(throws: UnsupportedModelError.self) { _ = try ParakeetBackend.installFolderName(for: "unknown-id") }
    }

    @Test func parakeetHfRepoIdResolvesShortIds() throws -> Void {
        #expect(
            try ParakeetBackend.huggingFaceRepoId(for: "v3")
                == "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        )
        #expect(
            try ParakeetBackend.huggingFaceRepoId(for: "tdt-ja")
                == "FluidInference/parakeet-0.6b-ja-coreml"
        )
    }
}
