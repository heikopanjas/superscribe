import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Transcriber availability", .serialized, ResetSharedStateTrait())
struct TranscriberAvailabilityTests {
    struct DefaultProbe: Transcriber {
        let modelId = "test"
        var capabilities: BackendCapabilities {
            return BackendCapabilities(
                requiredAudioFormat: .asr16kMono,
                displayName: "Probe",
                defaultModelId: "probe"
            )
        }

        func transcribe(
            samples: [Float],
            segment: SpeechSegment,
            config: TranscriptionConfig
        ) async throws -> SegmentTranscription {
            return SegmentTranscription(segment: segment, words: [])
        }
    }

    #if arch(arm64)
    @Test func defaultIsAvailableOnAppleSilicon() -> Void {
        #expect(DefaultProbe.isAvailable == true)
        #expect(ParakeetBackend.isAvailable == true)
        #expect(WhisperBackend.isAvailable == true)
    }
    #endif
}
