import AVFoundation
import Foundation

/// Progress update emitted while `AudioPreparer` is converting a file.
public struct ConversionProgress: Sendable {
    /// Source file being converted.
    public let source: URL
    /// Source frames processed so far.
    public let framesProcessed: Int64
    /// Total source frames in the file (0 if unknown).
    public let framesTotal: Int64
    /// 0…1 fraction. 1.0 once the file has been fully consumed.
    public let fraction: Double
}
