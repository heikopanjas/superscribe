import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech asset installer", .serialized, ResetSharedStateTrait())
struct AppleSpeechAssetInstallerTests {
    @Test func isInstalledFalseWhenRuntimeUnavailable() async {
        let prior = AppleSpeechSupport.testForceRuntimeUnavailable
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        defer { AppleSpeechSupport.testForceRuntimeUnavailable = prior }
        #expect(await AppleSpeechAssetInstaller.isInstalled(localeId: "en-US") == false)
    }

    @Test func isInstalledFalseWhenAPIForcedOff() async {
        let prior = AppleSpeechSupport.testForceAPIAvailabilityFalse
        AppleSpeechSupport.testForceAPIAvailabilityFalse = true
        defer { AppleSpeechSupport.testForceAPIAvailabilityFalse = prior }
        #expect(await AppleSpeechAssetInstaller.isInstalled(localeId: "en-US") == false)
    }

    @Test func ensureInstalledUsesDefaultProgressHandler() async throws {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["en-US"]
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["en-US"]
            defer {
                AppleSpeechLiveAPI.testInstalledLocaleIds = nil
                AppleSpeechLiveAPI.testSupportedLocaleIds = nil
            }
            let url = try await AppleSpeechAssetInstaller.ensureInstalled(
                localeId: "en-US",
                backend: .appleSpeech,
                onProgress: { _ in }
            )
            #expect(url.scheme == "apple-speech")
        }
    }

    @Test func ensureInstalledThrowsWhenAPIForcedOff() async {
        let prior = AppleSpeechSupport.testForceAPIAvailabilityFalse
        AppleSpeechSupport.testForceAPIAvailabilityFalse = true
        defer { AppleSpeechSupport.testForceAPIAvailabilityFalse = prior }
        await #expect(throws: BackendTranscriberError.self) {
            _ = try await AppleSpeechAssetInstaller.ensureInstalled(
                localeId: "en-US",
                backend: .appleSpeech,
                onProgress: { _ in }
            )
        }
    }

    @Test func ensureInstalledThrowsWhenRuntimeUnavailable() async {
        let prior = AppleSpeechSupport.testForceRuntimeUnavailable
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        defer { AppleSpeechSupport.testForceRuntimeUnavailable = prior }
        await #expect(throws: BackendTranscriberError.self) {
            _ = try await AppleSpeechAssetInstaller.ensureInstalled(
                localeId: "en-US",
                backend: .appleSpeech,
                onProgress: { _ in }
            )
        }
    }

    @Test func isInstalledUsesStubLocales() async {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["fr-FR"]
            defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }
            #expect(await AppleSpeechAssetInstaller.isInstalled(localeId: "fr-FR") == true)
            #expect(await AppleSpeechAssetInstaller.isInstalled(localeId: "en-US") == false)
        }
        else {
            #expect(await AppleSpeechAssetInstaller.isInstalled(localeId: "en-US") == false)
        }
    }

    @Test func ensureInstalledThrowsForUnsupportedLocale() async {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testForceUnsupportedLocale = true
            defer { AppleSpeechLiveAPI.testForceUnsupportedLocale = false }
            await #expect(throws: AppleSpeechError.self) {
                _ = try await AppleSpeechAssetInstaller.ensureInstalled(
                    localeId: "xx-XX",
                    backend: .appleSpeech,
                    onProgress: { _ in }
                )
            }
        }
    }

    @Test func releaseNoOpWhenRuntimeUnavailable() async {
        let prior = AppleSpeechSupport.testForceRuntimeUnavailable
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        defer { AppleSpeechSupport.testForceRuntimeUnavailable = prior }
        await AppleSpeechAssetInstaller.release(localeId: "en-US")
    }

    @Test func ensureInstalledSkipsWhenAlreadyInstalled() async throws {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["en-US"]
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["en-US"]
            defer {
                AppleSpeechLiveAPI.testInstalledLocaleIds = nil
                AppleSpeechLiveAPI.testSupportedLocaleIds = nil
            }
            let url = try await AppleSpeechAssetInstaller.ensureInstalled(
                localeId: "en-US",
                backend: .appleSpeech,
                onProgress: { _ in }
            )
            #expect(url.scheme == "apple-speech")
        }
    }
}
