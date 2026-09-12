import Foundation
import Testing

@testable import SuperscribeKit

internal final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value: DownloadProgress?
    func store(_ progress: DownloadProgress) -> Void {
        self.lock.lock()
        self.value = progress
        self.lock.unlock()
    }
}
