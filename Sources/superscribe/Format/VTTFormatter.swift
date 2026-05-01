import Foundation

/// Renders `MergedSegment`s as a WebVTT document.
public struct VTTFormatter: Sendable {
    public var includeWords: Bool

    public init(includeWords: Bool = false) {
        self.includeWords = includeWords
    }

    public func render(_ segments: [MergedSegment]) -> String {
        var output = "WEBVTT\n"
        for segment in segments {
            output += "\n"
            output += "\(Self.timestamp(segment.start)) --> \(Self.timestamp(segment.end))\n"
            output += "<v \(segment.speaker)>"
            output += body(for: segment)
            output += "\n"
        }
        return output
    }

    private func body(for segment: MergedSegment) -> String {
        guard includeWords, !segment.words.isEmpty else {
            return segment.words.map(\.text).joined(separator: " ")
        }
        // Inline word timestamps: `<00:00:01.230>word`.
        return segment.words
            .map { "<\(Self.timestamp($0.start))>\($0.text)" }
            .joined(separator: " ")
    }

    /// Format a duration as `HH:MM:SS.mmm` (always; spec-compliant for VTT).
    static func timestamp(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let totalMillis = Int((clamped * 1000.0).rounded())
        let millis = totalMillis % 1000
        let totalSeconds = totalMillis / 1000
        let s = totalSeconds % 60
        let m = (totalSeconds / 60) % 60
        let h = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, millis)
    }
}
