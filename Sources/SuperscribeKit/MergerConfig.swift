import Foundation

/// Configuration for the merge pipeline.
public struct MergerConfig: Sendable, Hashable {
    public var overlapPolicy: OverlapPolicy
    public var gapThreshold: TimeInterval
    public var maxCueDuration: TimeInterval?
    /// Maximum gap between same-speaker segments to coalesce them.
    public var maxCoalesceGap: TimeInterval

    public init(
        overlapPolicy: OverlapPolicy = .preserve,
        gapThreshold: TimeInterval = 3.0,
        maxCueDuration: TimeInterval? = nil,
        maxCoalesceGap: TimeInterval = 1.0
    ) {
        self.overlapPolicy = overlapPolicy
        self.gapThreshold = gapThreshold
        self.maxCueDuration = maxCueDuration
        self.maxCoalesceGap = maxCoalesceGap
    }
}

extension MergerConfig {
    public func validate() throws -> Void {
        guard self.gapThreshold.isFinite == true, self.gapThreshold >= 0, self.maxCoalesceGap.isFinite == true, self.maxCoalesceGap >= 0 else {
            throw InputValidationError("Merge gaps must be finite and nonnegative")
        }
        if let duration = self.maxCueDuration, duration.isFinite == false || duration <= 0 {
            throw InputValidationError("Maximum cue duration must be finite and positive")
        }
    }
}
