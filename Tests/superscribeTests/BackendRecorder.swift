import Foundation

@testable import SuperscribeKit

/// Thread-safe record of the backends reported by download progress callbacks.
final class BackendRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Backend?] = []

    var values: [Backend?] {
        return self.lock.withLock { self.recorded }
    }

    func record(_ backend: Backend?) -> Void {
        self.lock.withLock { self.recorded.append(backend) }
    }
}
