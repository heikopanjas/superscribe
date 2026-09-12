import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

internal final class PipelineRunProbe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var backend: Backend?
    private(set) var clearedProgress = false

    func setBackend(_ backend: Backend) -> Void {
        self.lock.lock()
        self.backend = backend
        self.lock.unlock()
    }

    func markCleared() -> Void {
        self.lock.lock()
        self.clearedProgress = true
        self.lock.unlock()
    }
}
