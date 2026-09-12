import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech model installer", .serialized, ResetSharedStateTrait())
struct AppleSpeechModelInstallerTests {
    @Test func installDownloadsWhenLocaleMissing() async throws -> Void {
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
                repoURL: try AppleSpeechSupport.catalogRepoURL
            )
            let url = try await ModelInstaller.install(model: model, backend: .appleSpeech)
            #expect(url.scheme == "apple-speech")
        }
    }

    @Test func installUsesAssetInstallerPath() async throws -> Void {
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
                repoURL: try AppleSpeechSupport.catalogRepoURL
            )
            let url = try await ModelInstaller.install(model: model, backend: .appleSpeech)
            #expect(url.scheme == "apple-speech")
        }
    }

    @Test func removalPathsReturnsMarkerForIncompleteReservation() async throws -> Void {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testReservedLocaleIds = ["fr-FR"]
            defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }
            let paths = try await ModelInstaller.removalPaths(modelId: "fr-FR", backend: .appleSpeech)
            #expect(paths.count == 1)
            #expect(try #require(paths.first).host == "locale")
        }
    }

    @Test func isInstalledRecognisesMarkerForInstalledLocale() async throws -> Void {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["it-IT"]
            defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }
            let marker = try AppleSpeechSupport.installMarkerURL(for: "it-IT")
            #expect(await ModelInstaller.isInstalled(at: marker, backend: .appleSpeech) == true)
        }
    }
    @Test func removalConfirmationUsesEquivalentLocaleIdentity() async throws -> Void {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testReservedLocaleIds = ["en-US"]
            let paths = try await ModelInstaller.removalPaths(modelId: "en_US", backend: .appleSpeech)
            #expect(paths == [try AppleSpeechSupport.installMarkerURL(for: "en-US")])
        }
    }
}
