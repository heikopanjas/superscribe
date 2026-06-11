import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech backend", .serialized, ResetSharedStateTrait())
struct AppleSpeechBackendTests {
    @Test func makeTranscriberUnavailableWhenForced() {
        if #available(macOS 26, *) {
            let prior = AppleSpeechBackend.testForceUnavailable
            AppleSpeechBackend.testForceUnavailable = true
            defer { AppleSpeechBackend.testForceUnavailable = prior }
            #expect(throws: BackendTranscriberError.self) {
                _ = try Backend.appleSpeech.makeTranscriber(model: "en-US")
            }
        }
    }

    @Test func transcribeMapsStubSpans() async throws {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testTranscriptionSpans = [
                .init(text: "hello", start: 0.0, end: 0.3),
            ]
            defer { AppleSpeechLiveAPI.testTranscriptionSpans = nil }

            AppleSpeechBackend.testLoadHook = {
                .init(locale: Locale(identifier: "en_US"), localeId: "en-US")
            }
            defer { AppleSpeechBackend.testLoadHook = nil }

            let backend = AppleSpeechBackend(model: "en-US")
            let segment = SpeechSegment(start: 5.0, end: 6.0)
            let config = TranscriptionConfig(language: "en", model: "en-US", prompt: nil)
            let result = try await backend.transcribe(
                samples: [0.1, 0.2, 0.3],
                segment: segment,
                config: config
            )
            #expect(result.words.count == 1)
            #expect(result.words[0].text == "hello")
            #expect(result.words[0].start == 5.0)
        }
    }

    @Test func ensureLoadedBuildsSessionFromInstalledLocale() async throws {
        if #available(macOS 26, *) {
            AppleSpeechBackend.testLoadHook = nil
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["en-US"]
            AppleSpeechLiveAPI.testSupportedLocaleIds = ["en-US"]
            defer {
                AppleSpeechLiveAPI.testInstalledLocaleIds = nil
                AppleSpeechLiveAPI.testSupportedLocaleIds = nil
            }

            let backend = AppleSpeechBackend(model: "en-US")
            let segment = SpeechSegment(start: 0.0, end: 1.0)
            let config = TranscriptionConfig(language: nil, model: "en-US", prompt: nil)
            AppleSpeechLiveAPI.testTranscriptionSpans = []
            defer { AppleSpeechLiveAPI.testTranscriptionSpans = nil }
            _ = try await backend.transcribe(samples: [0.1], segment: segment, config: config)
        }
    }

    @Test func ensureLoadedThrowsForUnsupportedLocale() async throws {
        if #available(macOS 26, *) {
            AppleSpeechBackend.testLoadHook = nil
            AppleSpeechLiveAPI.testInstalledLocaleIds = ["en-US"]
            AppleSpeechLiveAPI.testForceUnsupportedLocale = true
            defer {
                AppleSpeechLiveAPI.testInstalledLocaleIds = nil
                AppleSpeechLiveAPI.testForceUnsupportedLocale = false
            }

            let backend = AppleSpeechBackend(model: "en-US")
            let segment = SpeechSegment(start: 0.0, end: 1.0)
            let config = TranscriptionConfig(language: nil, model: "en-US", prompt: nil)
            await #expect(throws: AppleSpeechError.self) {
                _ = try await backend.transcribe(
                    samples: [0.1],
                    segment: segment,
                    config: config
                )
            }
        }
    }

    @Test func transcribeThrowsWhenInstallMissing() async throws {
        if #available(macOS 26, *) {
            AppleSpeechBackend.testLoadHook = nil
            AppleSpeechLiveAPI.testInstalledLocaleIds = []
            defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }

            let backend = AppleSpeechBackend(model: "en-US")
            let segment = SpeechSegment(start: 0.0, end: 1.0)
            let config = TranscriptionConfig(language: nil, model: "en-US", prompt: nil)
            await #expect(throws: ModelInstallationError.self) {
                _ = try await backend.transcribe(
                    samples: [0.1],
                    segment: segment,
                    config: config
                )
            }
        }
    }
}
