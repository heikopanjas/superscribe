import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech registry", .serialized, ResetSharedStateTrait())
struct AppleSpeechRegistryTests {
    @Test func catalogDefaultModelIdMatchesSupport() -> Void {
        #expect(AppleSpeechCatalog.defaultModelId == AppleSpeechSupport.defaultLocaleId)
    }

    @Test func remoteModelsUsesStubLocales() async throws -> Void {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["en-US", "de-DE"]
            defer { AppleSpeechLiveAPI.testSupportedLocaleIds = nil }
            let models = try await AppleSpeechCatalog.remoteModels()
            #expect(models.count == 2)
            #expect(models[0].repoId == AppleSpeechSupport.catalogRepoId)
            #expect(models.contains(where: { $0.id == "en-US" }) == true)
        }
        else {
            let models = try await AppleSpeechCatalog.remoteModels()
            #expect(models.isEmpty == true)
        }
    }

    @Test func installedModelsUsesStubLocales() async throws -> Void {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["en-US"]
            defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }
            let models = try await AppleSpeechCatalog.installedModels()
            #expect(models.count == 1)
            #expect(models[0].path.scheme == "apple-speech")
        }
        else {
            let models = try await AppleSpeechCatalog.installedModels()
            #expect(models.isEmpty == true)
        }
    }

    @Test func catalogReturnsEmptyWhenAPIForcedOff() async throws -> Void {
        let prior = AppleSpeechSupport.testForceAPIAvailabilityFalse
        AppleSpeechSupport.testForceAPIAvailabilityFalse = true
        defer { AppleSpeechSupport.testForceAPIAvailabilityFalse = prior }
        #expect(try await AppleSpeechCatalog.remoteModels().isEmpty == true)
        #expect(try await AppleSpeechCatalog.installedModels().isEmpty == true)
    }

    @Test func catalogReturnsEmptyWhenRuntimeForcedUnavailable() async throws -> Void {
        let prior = AppleSpeechSupport.testForceRuntimeUnavailable
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        defer { AppleSpeechSupport.testForceRuntimeUnavailable = prior }
        #expect(try await AppleSpeechCatalog.remoteModels().isEmpty == true)
        #expect(try await AppleSpeechCatalog.installedModels().isEmpty == true)
        #expect(throws: ModelInstallationError.self) {
            _ = try AppleSpeechCatalog.installPath(for: "en-US")
        }
    }

    @Test func installPathReturnsMarkerWhenRuntimeAvailable() throws -> Void {
        if AppleSpeechSupport.isRuntimeAvailable() == true {
            let path = try AppleSpeechCatalog.installPath(for: "en-US")
            #expect(path.absoluteString.contains("apple-speech://locale/en-US") == true)
        }
        else {
            #expect(throws: ModelInstallationError.self) {
                _ = try AppleSpeechCatalog.installPath(for: "en-US")
            }
        }
    }
}
