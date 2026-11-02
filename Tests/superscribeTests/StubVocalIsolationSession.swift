import Foundation

@testable import SuperscribeKit

internal actor StubVocalIsolationSession: VocalIsolationSession {
    nonisolated let sampleRate: Int
    nonisolated let channels: Int
    private(set) var sizes: [Int] = []
    private let invalid: Bool
    private let onSection: @Sendable () async throws -> Void

    init(sampleRate: Int = 16_000, channels: Int = 2, invalid: Bool = false, onSection: @Sendable @escaping () async throws -> Void = {}) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.invalid = invalid
        self.onSection = onSection
    }

    func vocals(samples: [Float], frames: Int) async throws -> [Float] {
        self.sizes.append(frames)
        try await self.onSection()
        try Task.checkCancellation()
        if self.invalid == true { return [.nan] }
        return Array(samples.prefix(frames))
    }
}
