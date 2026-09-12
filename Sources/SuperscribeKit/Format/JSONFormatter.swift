import Foundation

public struct JSONFormatter: TranscriptFormatter {
    public init() {}

    public func render(_ segments: [MergedSegment]) throws -> String {
        let document = MergedTranscriptDocument(segments: try TranscriptValidation.normalized(segments))
        return String(decoding: try JSONCoding.configEncoder().encode(document), as: UTF8.self) + "\n"
    }
}
