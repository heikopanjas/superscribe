import Foundation
import Testing

@testable import SuperscribeKit

internal struct ControlledTranscriber: Transcriber {
    let modelId = "controlled"
    let operation: @Sendable (SpeechSegment) async throws -> [TimedWord]
    var capabilities: BackendCapabilities { return .init(requiredAudioFormat: .asr16kMono, displayName: "Controlled", defaultModelId: self.modelId) }
    func transcribe(samples: [Float], segment: SpeechSegment, config: TranscriptionConfig) async throws -> SegmentTranscription {
        return try await .init(segment: segment, words: self.operation(segment))
    }
}
