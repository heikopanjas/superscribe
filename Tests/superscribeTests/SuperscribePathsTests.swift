import Foundation
import Testing

@testable import SuperscribeKit

@Suite("SuperscribePaths", .serialized, ResetSharedStateTrait())
struct SuperscribePathsTests {
    private func home() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }

    @Test func userConfigDirectory() -> Void {
        let path = SuperscribePaths.userConfigDirectory()
        #expect(path.path == self.home().appendingPathComponent(".config/superscribe").path)
    }

    @Test func catalogCacheDirectory() -> Void {
        let path = SuperscribePaths.catalogCacheDirectory()
        #expect(path.path == self.home().appendingPathComponent(".cache/superscribe").path)
    }

    @Test func audioCacheRoot() -> Void {
        let path = SuperscribePaths.audioCacheRoot()
        #expect(path.path == self.home().appendingPathComponent(".cache/superscribe/audio").path)
    }

    @Test func whisperModelCacheDirectory() throws -> Void {
        SuperscribePaths.overrideWhisperModelCacheDirectory = nil
        let path = SuperscribePaths.whisperModelCacheDirectory()
        let caches = (try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first))
        #expect(path.path == caches.appendingPathComponent("superscribe/whisper").path)
    }

    @Test func fluidAudioModelsDirectory() throws -> Void {
        SuperscribePaths.overrideFluidAudioModelsDirectory = nil
        let path = SuperscribePaths.fluidAudioModelsDirectory()
        let appSupport = (try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first))
        #expect(
            path.path
                == appSupport.appendingPathComponent("FluidAudio/Models").path
        )
    }
}
