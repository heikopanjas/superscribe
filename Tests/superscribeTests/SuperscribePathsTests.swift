import Foundation
import Testing

@testable import SuperscribeKit

@Suite("SuperscribePaths")
struct SuperscribePathsTests {
    private func home() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    @Test func userConfigDirectory() {
        let path = SuperscribePaths.userConfigDirectory()
        #expect(path.path == home().appendingPathComponent(".config/superscribe").path)
    }

    @Test func catalogCacheDirectory() {
        let path = SuperscribePaths.catalogCacheDirectory()
        #expect(path.path == home().appendingPathComponent(".cache/superscribe").path)
    }

    @Test func audioCacheRoot() {
        let path = SuperscribePaths.audioCacheRoot()
        #expect(path.path == home().appendingPathComponent(".cache/superscribe/audio").path)
    }

    @Test func whisperModelCacheDirectory() {
        let path = SuperscribePaths.whisperModelCacheDirectory()
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        #expect(path.path == caches.appendingPathComponent("superscribe/whisper").path)
    }

    @Test func fluidAudioModelsDirectory() {
        let path = SuperscribePaths.fluidAudioModelsDirectory()
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #expect(
            path.path
                == appSupport.appendingPathComponent("FluidAudio/Models").path
        )
    }
}
