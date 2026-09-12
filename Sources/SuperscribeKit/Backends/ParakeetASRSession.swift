import FluidAudio
import Foundation

/// Test seam over FluidAudio's `AsrManager` for unit tests without on-disk models.
internal protocol ParakeetASRSession: Sendable {
    var decoderLayerCount: Int { get async }
    func transcribe(
        _ samples: [Float],
        decoderState: inout TdtDecoderState,
        language: Language?
    ) async throws -> ASRResult
}
