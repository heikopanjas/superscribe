import Foundation

/// Strategy for handling time-overlapping segments from different speakers
/// (i.e. crosstalk).
public enum OverlapPolicy: String, CaseIterable, Sendable, Codable {
    case preserve, trim, interleave
}
