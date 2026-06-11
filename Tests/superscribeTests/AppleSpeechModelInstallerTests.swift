import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech model installer", .serialized, ResetSharedStateTrait())
struct AppleSpeechModelInstallerTests {
    @Test func installDownloadsWhenLocaleMissing() async throws {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = []
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["es-ES"]
            AppleSpeechLiveAPI.testSkipLocaleInstall = true
            defer {
                AppleSpeechLiveAPI.testInstalledLocaleIds = nil
                AppleSpeechLiveAPI.testSupportedLocaleIds = nil
                AppleSpeechLiveAPI.testSkipLocaleInstall = false
            }

            let model = RemoteModelInfo(
                id: "es-ES",
                repoId: AppleSpeechSupport.catalogRepoId,
                repoURL: AppleSpeechSupport.catalogRepoURL
            )
            let url = try await ModelInstaller.install(model: model, backend: .appleSpeech)
            #expect(url.scheme == "apple-speech")
        }
    }

    @Test func installUsesAssetInstallerPath() async throws {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["de-DE"]
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["de-DE"]
            defer {
                AppleSpeechLiveAPI.testInstalledLocaleIds = nil
                AppleSpeechLiveAPI.testSupportedLocaleIds = nil
            }

            let model = RemoteModelInfo(
                id: "de-DE",
                repoId: AppleSpeechSupport.catalogRepoId,
                repoURL: AppleSpeechSupport.catalogRepoURL
            )
            let url = try await ModelInstaller.install(model: model, backend: .appleSpeech)
            #expect(url.scheme == "apple-speech")
        }
    }

    @Test func removalPathsReturnsMarkerWhenInstalled() async throws {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["fr-FR"]
            defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }
            let paths = try await ModelInstaller.removalPaths(modelId: "fr-FR", backend: .appleSpeech)
            #expect(paths.count == 1)
            #expect(paths[0].host == "locale")
        }
    }

    @Test func isInstalledRecognisesMarkerForInstalledLocale() async {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["it-IT"]
            defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }
            let marker = AppleSpeechSupport.installMarkerURL(for: "it-IT")
            #expect(await ModelInstaller.isInstalled(at: marker, backend: .appleSpeech) == true)
        }
    }
}
