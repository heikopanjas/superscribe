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

    @Test func modelsLiveUnderTheSuperscribeCache() -> Void {
        SuperscribePaths.overrideModelsDirectory = nil
        let models = self.home().appendingPathComponent(".cache/superscribe/models")
        #expect(SuperscribePaths.modelsDirectory().path == models.path)
        #expect(SuperscribePaths.parakeetModelsDirectory().path == models.appendingPathComponent("parakeet").path)
        #expect(SuperscribePaths.whisperModelsDirectory().path == models.appendingPathComponent("whisper").path)
        #expect(SuperscribePaths.diarizerModelsDirectory().path == models.appendingPathComponent("diarizer").path)
    }

    @Test func taskLocalModelsDirectoryTakesPrecedence() async -> Void {
        let override = URL(fileURLWithPath: "/override/models")
        let task = URL(fileURLWithPath: "/task/models")
        SuperscribePaths.overrideModelsDirectory = override
        #expect(SuperscribePaths.modelsDirectory() == override)
        SuperscribePaths.$taskModelsDirectory.withValue(task) {
            #expect(SuperscribePaths.parakeetModelsDirectory().path == "/task/models/parakeet")
        }
    }
}
