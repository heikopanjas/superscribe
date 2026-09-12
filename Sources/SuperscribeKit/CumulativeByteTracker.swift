import Darwin
import Foundation

// MARK: - Progress throttling

internal actor CumulativeByteTracker {
    private var bytes: Int64 = 0

    func add(_ chunk: Int64) -> Int64 {
        self.bytes += chunk
        return self.bytes
    }
}
