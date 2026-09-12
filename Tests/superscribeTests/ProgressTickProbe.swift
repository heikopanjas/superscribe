import Foundation
import Testing

@testable import SuperscribeKit

internal final class ProgressTickProbe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    func tick() -> Void {
        self.lock.lock()
        self.count += 1
        self.lock.unlock()
    }
}
