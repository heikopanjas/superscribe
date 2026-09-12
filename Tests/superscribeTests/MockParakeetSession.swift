import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Mock session

internal struct MockParakeetSession: ParakeetASRSession {
    let result: ASRResult

    var decoderLayerCount: Int {
        get async { return 1 }
    }

    func transcribe(
        _ samples: [Float],
        decoderState: inout TdtDecoderState,
        language: Language?
    ) async throws -> ASRResult {
        return self.result
    }
}
