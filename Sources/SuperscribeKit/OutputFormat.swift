import Foundation

/// Output format for the merged transcript.
public enum OutputFormat: String, CaseIterable, Sendable, Codable {
    case vtt, srt, json, txt
}
