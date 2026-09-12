import Foundation

public protocol TranscriptFormatter: Sendable {
    func render(_ segments: [MergedSegment]) throws -> String
}
