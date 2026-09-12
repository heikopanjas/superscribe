import Foundation
import SuperscribeKit

struct PipelineRunOptions: Sendable {
    let cliBackend: Backend?
    let cliModel: String?
    let tracks: [TrackInput]
    let transcriptionConfig: TranscriptionConfig
    let analyzerConfig: AnalyzerConfig
    let useCache: Bool
}
