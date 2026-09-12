import Foundation

/// Joins URLSession invalidation before the owning test releases its handler.
final class MockSessionLifetime: NSObject, URLSessionDelegate, Sendable {
    let invalidated = TestSignal()

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) -> Void {
        self.invalidated.signal()
    }
}
