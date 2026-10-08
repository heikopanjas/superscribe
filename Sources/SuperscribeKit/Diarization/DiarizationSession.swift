import Foundation

/// Stateful streaming diarization over one recording; confined to a single blocking worker.
internal protocol DiarizationSession: Sendable {
    var speakerCount: Int { get }
    var frameDuration: TimeInterval { get }
    /// Buffers samples and returns the row-major probabilities of every frame they complete.
    func append(_ samples: [Float]) throws -> [Float]
    /// Flushes the tail and returns the remaining frame probabilities.
    func finish() throws -> [Float]
}
