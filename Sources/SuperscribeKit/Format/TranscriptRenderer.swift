import Foundation

public enum TranscriptRenderer {
    public static func render(_ transcript: IntermediateTranscript, configuration: RenderConfiguration = RenderConfiguration()) throws -> String {
        try configuration.validate()
        let segments = try Merger(config: configuration.mergerConfig).merge(transcript)
        let formatter: any TranscriptFormatter
        switch configuration.format {
            case .vtt: formatter = VTTFormatter(includeWords: configuration.includeWords, maxLineLength: configuration.maxLineLength)
            case .srt: formatter = SRTFormatter(includeWords: configuration.includeWords, maxLineLength: configuration.maxLineLength)
            case .txt: formatter = TXTFormatter(includeWords: configuration.includeWords)
            case .json: formatter = JSONFormatter()
        }
        return try formatter.render(segments)
    }
}
