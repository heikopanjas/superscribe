import Foundation
import SuperscribeKit

struct PipelineRunResult: Sendable {
    let transcript: IntermediateTranscript
    let duration: TimeInterval
    let backend: Backend
    let model: String
}
