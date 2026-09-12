import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech support", .serialized, ResetSharedStateTrait())
struct AppleSpeechSupportTests {
    @Test func normalizeLocaleIdReplacesUnderscores() -> Void {
        #expect(AppleSpeechSupport.normalizeLocaleId("en_US") == "en-US")
    }

    @Test func installMarkerRoundTrip() throws -> Void {
        let url = try AppleSpeechSupport.installMarkerURL(for: "de-DE")
        #expect(AppleSpeechSupport.localeId(fromInstallMarker: url) == "de-DE")
    }

    @Test func localeIdFromInvalidMarkerReturnsNil() throws -> Void {
        let url = (try #require(URL(string: "file:///tmp/x")))
        #expect(AppleSpeechSupport.localeId(fromInstallMarker: url) == nil)
        #expect(throws: CocoaError.self) { _ = try AppleSpeechSupport.installMarkerURL(for: "") }
        let emptyId = try #require(URL(string: "apple-speech://locale/"))
        #expect(AppleSpeechSupport.localeId(fromInstallMarker: emptyId) == nil)
    }

    @Test func defaultLocaleIdIsNonEmpty() -> Void {
        #expect(AppleSpeechSupport.defaultLocaleId.isEmpty == false)
    }

    @Test func defaultLocaleIdFallsBackWhenIdentifierEmpty() -> Void {
        AppleSpeechSupport.testDefaultLocaleIdentifierOverride = ""
        defer { AppleSpeechSupport.testDefaultLocaleIdentifierOverride = nil }
        #expect(AppleSpeechSupport.defaultLocaleId == "en-US")
    }

    @Test func unavailableMessageIncludesMacOSVersion() -> Void {
        #expect(AppleSpeechSupport.unavailableMessage().contains("macOS") == true)
    }

    @Test func localeFromEmptyModelUsesDefault() -> Void {
        let locale = AppleSpeechSupport.locale(fromModelId: "   ")
        #expect(locale.identifier.isEmpty == false)
    }

    @Test func isRuntimeAvailableHonorsForceFlag() -> Void {
        let prior = AppleSpeechSupport.testForceRuntimeUnavailable
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        defer { AppleSpeechSupport.testForceRuntimeUnavailable = prior }
        #expect(AppleSpeechSupport.isRuntimeAvailable() == false)
    }
}
