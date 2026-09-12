import AVFoundation
import CoreML
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Mock transcriber

/// A deterministic transcriber for testing: returns one word per segment
/// with text "mock-word".
struct MockTranscriber: Transcriber {
    var modelId = "mock"
    static var isAvailable: Bool { return true }

    var capabilities: BackendCapabilities {
        return BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Mock",
            defaultModelId: "mock"
        )
    }

    func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        let word = TimedWord(
            text: "mock-word",
            start: segment.start,
            end: segment.end
        )
        return SegmentTranscription(segment: segment, words: [word])
    }
}
