import Darwin
import Foundation

/// Coordinates complete read-modify-write transactions across instances and processes.
internal enum FileTransaction {
    internal static let worker = BlockingWorker(label: "superscribe.filesystem")
    @TaskLocal internal static var lockOperation: @Sendable (Int32, Int32) -> Int32 = { descriptor, operation in
        return flock(descriptor, operation)
    }

    internal static func withLock<Value>(for url: URL, body: () throws -> Value) throws -> Value {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        guard Self.lockOperation(descriptor, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        // Closing the descriptor releases the lock, including after a throwing body.
        return try body()
    }
}
