import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech support", .serialized, ResetSharedStateTrait())
struct AppleSpeechSupportTests {
    @Test func normalizeLocaleIdReplacesUnderscores() {
        #expect(AppleSpeechSupport.normalizeLocaleId("en_US") == "en-US")
    }

    @Test func installMarkerRoundTrip() throws {
        let url = AppleSpeechSupport.installMarkerURL(for: "de-DE")
        #expect(AppleSpeechSupport.localeId(fromInstallMarker: url) == "de-DE")
    }

    @Test func localeIdFromInvalidMarkerReturnsNil() {
        let url = URL(string: "file:///tmp/x")!
        #expect(AppleSpeechSupport.localeId(fromInstallMarker: url) == nil)
        let emptyId = AppleSpeechSupport.installMarkerURL(for: "")
        #expect(AppleSpeechSupport.localeId(fromInstallMarker: emptyId) == nil)
    }

    @Test func defaultLocaleIdIsNonEmpty() {
        #expect(AppleSpeechSupport.defaultLocaleId.isEmpty == false)
    }

    @Test func defaultLocaleIdFallsBackWhenIdentifierEmpty() {
        AppleSpeechSupport.testDefaultLocaleIdentifierOverride = ""
        defer { AppleSpeechSupport.testDefaultLocaleIdentifierOverride = nil }
        #expect(AppleSpeechSupport.defaultLocaleId == "en-US")
    }

    @Test func unavailableMessageIncludesMacOSVersion() {
        #expect(AppleSpeechSupport.unavailableMessage().contains("macOS") == true)
    }

    @Test func localeFromEmptyModelUsesDefault() {
        let locale = AppleSpeechSupport.locale(fromModelId: "   ")
        #expect(locale.identifier.isEmpty == false)
    }

    @Test func isRuntimeAvailableHonorsForceFlag() {
        let prior = AppleSpeechSupport.testForceRuntimeUnavailable
        AppleSpeechSupport.testForceRuntimeUnavailable = true
        defer { AppleSpeechSupport.testForceRuntimeUnavailable = prior }
        #expect(AppleSpeechSupport.isRuntimeAvailable() == false)
    }
}
