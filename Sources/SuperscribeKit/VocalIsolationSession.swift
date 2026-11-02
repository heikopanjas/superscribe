import Foundation

/// One reusable inference session; PCM is planar and output is mono.
internal protocol VocalIsolationSession: Sendable {
    var sampleRate: Int { get }
    var channels: Int { get }
    func vocals(samples: [Float], frames: Int) async throws -> [Float]
}
