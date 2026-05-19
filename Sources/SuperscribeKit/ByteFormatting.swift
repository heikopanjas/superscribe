import Foundation

/// Human-readable byte sizes for logs, errors, and CLI output.
public enum ByteFormatting {
    public static func format(_ bytes: Int64) -> String {
        let units: [(threshold: Double, suffix: String)] = [
            (1024 * 1024 * 1024, "GiB"),
            (1024 * 1024, "MiB"),
            (1024, "KiB")
        ]
        let value = Double(bytes)
        for (threshold, suffix) in units where value >= threshold {
            return String(format: "%.1f %@", value / threshold, suffix)
        }
        return "\(bytes) B"
    }
}
