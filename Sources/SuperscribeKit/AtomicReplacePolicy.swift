import Darwin
import Foundation

/// How to resolve a collision when promoting a staged path to its final location.
public enum AtomicReplacePolicy: Sendable {
    /// If `final` already exists, delete `staging` and leave `final` untouched.
    case discardStagingIfFinalExists
    /// Atomically replace `final`, preserving it if promotion fails.
    case replaceExisting
}
