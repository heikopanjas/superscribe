import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Whisper C invocation", .serialized, ResetSharedStateTrait())
struct WhisperInvocationTests {
    @Test(arguments: [nil, "", "Grüße 世界", String(repeating: "long prompt ", count: 2_000)] as [String?], [nil, "en", "auto"] as [String?])
    func stringsRemainAliveThroughInference(prompt: String?, language: String?) async throws -> Void {
        WhisperBackend.testUseStubLoad = true
        WhisperBackend.testWhisperAPISegments = []
        try await confirmation("Synchronous invocation") { invoked in
            try await WhisperLiveAPI.$invocation.withValue(
                { parameters, samples in
                    #expect(parameters.language.map { String(cString: $0) } == language)
                    #expect(parameters.initial_prompt.map { String(cString: $0) } == prompt)
                    #expect(parameters.detect_language == false)
                    #expect(parameters.abort_callback?(nil) == false)
                    #expect(parameters.abort_callback?(parameters.abort_callback_user_data) == false)
                    #expect(samples.count == 16_000)
                    invoked()
                    return 0
                },
                operation: {
                    _ = try await WhisperBackend(model: "stub-lifetime").transcribe(
                        samples: [0.1], segment: SpeechSegment(start: 0, end: 1),
                        config: TranscriptionConfig(language: language, prompt: prompt)
                    )
                })
        }
    }

    @Test func shortAudioDiscardsAndClampsPaddingWords() async throws -> Void {
        WhisperBackend.testUseStubLoad = true
        WhisperBackend.testWhisperAPISegments = [
            [
                WhisperTestToken(token: " crossing", id: 1, t0: 20, t1: 80),
                WhisperTestToken(token: " padding", id: 2, t0: 80, t1: 100)
            ]
        ]
        let result = try await WhisperBackend(model: "stub-padding").transcribe(
            samples: Array(repeating: 0.1, count: 8_000), segment: SpeechSegment(start: 5, end: 5.5),
            config: TranscriptionConfig(language: nil, prompt: nil)
        )
        #expect(result.segment == SpeechSegment(start: 5, end: 5.5))
        #expect(result.words == [TimedWord(text: "crossing", start: 5.2, end: 5.5)])
    }

    @Test func invalidLanguageThrows() async -> Void {
        WhisperBackend.testUseStubLoad = true
        WhisperBackend.testWhisperAPISegments = []
        await #expect(throws: WhisperError.self) {
            _ = try await WhisperBackend(model: "stub-language").transcribe(
                samples: [0.1], segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: "unsupported-language", prompt: nil)
            )
        }
        #expect(WhisperError.unsupportedLanguage("bad").errorDescription?.contains("bad") == true)
    }

    @Test func cancellationReachesInferenceAbortCallback() async -> Void {
        WhisperBackend.testUseStubLoad = true
        WhisperBackend.testWhisperAPISegments = []
        let entered = TestSignal()
        await WhisperLiveAPI.$invocation.withValue(
            { parameters, _ in
                entered.signal()
                while parameters.abort_callback?(parameters.abort_callback_user_data) == false {}
                return -1
            },
            operation: {
                let task = Task {
                    return try await WhisperBackend(model: "stub-cancel").transcribe(
                        samples: [0.1], segment: SpeechSegment(start: 0, end: 1),
                        config: TranscriptionConfig(language: nil, prompt: nil)
                    )
                }
                await entered.wait()
                task.cancel()
                await #expect(throws: CancellationError.self) { _ = try await task.value }
            })
    }

    @Test func emptyInputIsNotPadded() async throws -> Void {
        WhisperBackend.testUseStubLoad = true
        WhisperBackend.testWhisperAPISegments = []
        try await WhisperLiveAPI.$invocation.withValue(
            { _, samples in
                #expect(samples.isEmpty == true)
                return 0
            },
            operation: {
                _ = try await WhisperBackend(model: "stub-empty").transcribe(
                    samples: [], segment: SpeechSegment(start: 0, end: 1),
                    config: TranscriptionConfig(language: nil, prompt: nil)
                )
            })
    }
}
