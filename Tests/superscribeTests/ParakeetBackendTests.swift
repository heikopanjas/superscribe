import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ParakeetBackend", .serialized, ResetSharedStateTrait())
struct ParakeetBackendTests {

    private func displayName(for model: String) async throws -> String {
        let backend = try ParakeetBackend(model: model, injectedSession: nil)
        return backend.capabilities.displayName
    }

    @Test func publicInitUsesDefaultModel() async throws -> Void {
        let backend = try ParakeetBackend()
        #expect(backend.capabilities.displayName.contains("v3") == true)
    }

    @Test func modelStringSelectsReportedVariants() async throws -> Void {
        #expect(try await self.displayName(for: "v2").contains("v2") == true)
        #expect(try await self.displayName(for: "v3").contains("v3") == true)
        #expect(try await self.displayName(for: "tdt-ctc-110m").contains("tdtCtc110m") == true)
        #expect(try await self.displayName(for: "tdt-ja").contains("tdtJa") == true)
        #expect(throws: UnsupportedModelError.self) { _ = try ParakeetBackend(model: "bogus-unknown") }
        #expect(UnsupportedModelError(backend: .parakeet, model: "bogus").errorDescription?.contains("bogus") == true)
    }

    @Test(arguments: ["tdtctc110m", "110m", "tdtja", "ja", " V3 "])
    func aliasesUseDescriptorIdentity(alias: String) throws -> Void {
        let descriptor = try ParakeetBackend.descriptor(for: alias)
        #expect(descriptor.id.isEmpty == false)
        _ = try ParakeetBackend(model: alias)
    }

    @Test func transcribeMapsTokenTimings() async throws -> Void {
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
        let backend = try ParakeetBackend(model: "v3", injectedSession: mock)
        let segment = SpeechSegment(start: 2.0, end: 5.0)
        let cfg = TranscriptionConfig(language: "en", prompt: nil)
        let out = try await backend.transcribe(
            samples: [Float](repeating: 0, count: 100),
            segment: segment,
            config: cfg
        )
        #expect(out.words.isEmpty == false)
        #expect(out.words.first?.text.contains("hello") == true)
        #expect(out.words.first?.start ?? 0 >= segment.start)
    }

    @Test func transcribeFallsBackToPlainTextWhenNoTimings() async throws -> Void {
        let mock = MockParakeetSession(
            result: ASRResult(
                text: " hi ",
                confidence: 1,
                duration: 0.2,
                processingTime: 0.01,
                tokenTimings: nil
            )
        )
        let backend = try ParakeetBackend(model: "v3", injectedSession: mock)
        let segment = SpeechSegment(start: 1.0, end: 3.0)
        let cfg = TranscriptionConfig(language: nil, prompt: nil)
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

    @Test func transcribeEmptyTextYieldsNoWords() async throws -> Void {
        let mock = MockParakeetSession(
            result: ASRResult(
                text: "   ",
                confidence: 1,
                duration: 0.1,
                processingTime: 0.01,
                tokenTimings: nil
            )
        )
        let backend = try ParakeetBackend(model: "v3", injectedSession: mock)
        let out = try await backend.transcribe(
            samples: [],
            segment: SpeechSegment(start: 0, end: 1),
            config: TranscriptionConfig(language: nil, prompt: nil)
        )
        #expect(out.words.isEmpty == true)
    }

    @Test func transcribeThrowsWhenModelMissing() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { _, _ in
            let modelId = "tdt-ja"
            let backend = try ParakeetBackend(model: modelId, injectedSession: nil)
            await #expect(throws: ModelInstallationError.self) {
                _ = try await backend.transcribe(
                    samples: [0.01],
                    segment: SpeechSegment(start: 0, end: 1),
                    config: TranscriptionConfig(language: nil, prompt: nil)
                )
            }
        }
    }

    @Test func resultMappingDirectMergeAndOffsets() -> Void {
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
