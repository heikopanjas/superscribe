import Foundation

@testable import SuperscribeKit

/// Emits one frame per appended window plus one on finish, and records each window's sample count.
final class StubDiarizationSession: DiarizationSession, @unchecked Sendable {
    let speakerCount = 2
    let frameDuration: TimeInterval = 0.01

    private let lock = NSLock()
    private var windows: [Int] = []

    var appendedWindows: [Int] {
        return self.lock.withLock { self.windows }
    }

    func append(_ samples: [Float]) throws -> [Float] {
        self.lock.withLock { self.windows.append(samples.count) }
        return [1, 0]
    }

    func finish() throws -> [Float] {
        return [0, 1]
    }
}
