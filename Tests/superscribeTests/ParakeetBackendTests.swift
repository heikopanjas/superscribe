import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ParakeetBackend", .serialized, ResetSharedStateTrait())
struct ParakeetBackendTests {

    private func displayName(for model: String) async -> String {
        let backend = ParakeetBackend(model: model, injectedSession: nil)
        return backend.capabilities.displayName
    }

    @Test func modelStringSelectsReportedVariants() async {
        #expect(await displayName(for: "v2").contains("v2") == true)
        #expect(await displayName(for: "v3").contains("v3") == true)
        #expect(await displayName(for: "tdt-ctc-110m").contains("tdtCtc110m") == true)
        #expect(await displayName(for: "tdt-ja").contains("tdtJa") == true)
        #expect(await displayName(for: "bogus-unknown").contains("v3") == true)
    }

    @Test func shortIdForVersionMapsKnownAndFutureCases() {
        #expect(ParakeetBackend.shortIdForVersion(.v2) == "v2")
        #expect(ParakeetBackend.shortIdForVersion(.tdtCtc110m) == "tdt-ctc-110m")
        #expect(ParakeetBackend.shortIdForVersion(.ctcZhCn) == "v3")
    }

    @Test func transcribeMapsTokenTimings() async throws {
        let timings: [TokenTiming] = [
            TokenTiming(token: "▁hel", tokenId: 1, startTime: 0, endTime: 0.05, confidence: 1),
            TokenTiming(token: "lo", tokenId: 2, startTime: 0.05, endTime: 0.1, confidence: 1)
        ]
        let mock = MockParakeetSession(
            result: ASRResult(
                text: "hello",
                confidence: 1,
                duration: 0.1,
                processingTime: 0.01,
                tokenTimings: timings
            )
        )
        let backend = ParakeetBackend(model: "v3", injectedSession: mock)
        let segment = SpeechSegment(start: 2.0, end: 5.0)
        let cfg = TranscriptionConfig(language: "en", model: "v3", prompt: nil)
        let out = try await backend.transcribe(
            samples: [Float](repeating: 0, count: 100),
            segment: segment,
            config: cfg
        )
        #expect(out.words.isEmpty == false)
        #expect(out.words.first?.text.contains("hello") == true)
        #expect(out.words.first?.start ?? 0 >= segment.start)
    }

    @Test func transcribeFallsBackToPlainTextWhenNoTimings() async throws {
        let mock = MockParakeetSession(
            result: ASRResult(
                text: " hi ",
                confidence: 1,
                duration: 0.2,
                processingTime: 0.01,
                tokenTimings: nil
            )
        )
        let backend = ParakeetBackend(model: "v3", injectedSession: mock)
        let segment = SpeechSegment(start: 1.0, end: 3.0)
        let cfg = TranscriptionConfig(language: nil, model: "v3", prompt: nil)
        let out = try await backend.transcribe(
            samples: [Float](repeating: 0, count: 64),
            segment: segment,
            config: cfg
        )
        #expect(out.words.count == 1)
        #expect(out.words[0].text == "hi")
        #expect(out.words[0].start == segment.start)
        #expect(out.words[0].end == segment.end)
    }

    @Test func transcribeEmptyTextYieldsNoWords() async throws {
        let mock = MockParakeetSession(
            result: ASRResult(
                text: "   ",
                confidence: 1,
                duration: 0.1,
                processingTime: 0.01,
                tokenTimings: nil
            )
        )
        let backend = ParakeetBackend(model: "v3", injectedSession: mock)
        let out = try await backend.transcribe(
            samples: [],
            segment: SpeechSegment(start: 0, end: 1),
            config: TranscriptionConfig(language: nil, model: "v3", prompt: nil)
        )
        #expect(out.words.isEmpty == true)
    }

    @Test func transcribeThrowsWhenModelMissing() async throws {
        let modelId = "tdt-ja"
        let path = ParakeetBackend.installPath(for: modelId)
        guard FileManager.default.fileExists(atPath: path.path) == false else {
            return
        }

        let backend = ParakeetBackend(model: modelId, injectedSession: nil)
        await #expect(throws: ModelInstallationError.self) {
            _ = try await backend.transcribe(
                samples: [0.01],
                segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: nil, model: modelId, prompt: nil)
            )
        }
    }

    @Test func resultMappingDirectMergeAndOffsets() {
        let timings: [TokenTiming] = [
            TokenTiming(token: "▁a", tokenId: 1, startTime: 0, endTime: 0.02, confidence: 1),
            TokenTiming(token: "b", tokenId: 2, startTime: 0.02, endTime: 0.05, confidence: 1)
        ]
        let asr = ASRResult(
            text: "ab",
            confidence: 1,
            duration: 0.05,
            processingTime: 0.01,
            tokenTimings: timings
        )
        let segment = SpeechSegment(start: 10, end: 12)
        let mapped = ParakeetResultMapping.map(asr, segment: segment)
        #expect(mapped.words.count == 1)
        #expect(mapped.words[0].start >= 10)

        let merged = ParakeetResultMapping.mergeTokensIntoWords(timings, segmentOffset: 5)
        #expect(merged.isEmpty == false)
    }
}

// MARK: - Mock session

private struct MockParakeetSession: ParakeetASRSession {
    let result: ASRResult

    var decoderLayerCount: Int {
        get async { 1 }
    }

    func transcribe(
        _ samples: [Float],
        decoderState: inout TdtDecoderState,
        language: Language?
    ) async throws -> ASRResult {
        result
    }
}
