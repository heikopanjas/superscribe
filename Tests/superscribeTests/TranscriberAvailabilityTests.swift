import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Transcriber availability")
struct TranscriberAvailabilityTests {
    struct DefaultProbe: Transcriber {
        var capabilities: BackendCapabilities {
            BackendCapabilities(
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
            SegmentTranscription(segment: segment, words: [])
        }
    }

    #if arch(arm64)
    @Test func defaultIsAvailableOnAppleSilicon() {
        #expect(DefaultProbe.isAvailable == true)
        #expect(ParakeetBackend.isAvailable == true)
        #expect(WhisperBackend.isAvailable == true)
    }
    #endif
}
