import Foundation

internal enum SubtitleTimestamp {
    internal static func milliseconds(_ seconds: TimeInterval) -> Int64 { return Int64((seconds * 1000).rounded()) }

    internal static func string(milliseconds: Int64, comma: Bool = false) -> String {
        let separator =
            if comma == true { "," }
            else { "." }
        return String(format: "%02lld:%02lld:%02lld", milliseconds / 3_600_000, (milliseconds / 60_000) % 60, (milliseconds / 1000) % 60)
            + separator + String(format: "%03lld", milliseconds % 1000)
    }

    internal static func bounds(_ segment: MergedSegment) -> (Int64, Int64) {
        let start = Self.milliseconds(segment.start)
        return (start, max(start + 1, Self.milliseconds(segment.end)))
    }
}
