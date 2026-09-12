import Foundation

/// Drains both pipes while waiting for process termination and joins cleanup on cancellation.
internal enum ProcessRunner {
    internal struct Output: Sendable {
        internal let status: Int32
        internal let stdout: Data
        internal let stderr: Data
    }

    internal static func run(executable: URL, arguments: [String], onStarted: @Sendable () -> Void = {}) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let cancelled = CancellationFlag()
        return try await withTaskCancellationHandler {
            async let output = BlockingWorker(label: "superscribe.process.stdout").run { _ in return stdout.fileHandleForReading.readDataToEndOfFile() }
            async let errors = BlockingWorker(label: "superscribe.process.stderr").run { _ in return stderr.fileHandleForReading.readDataToEndOfFile() }
            let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { terminated in continuation.resume(returning: terminated.terminationStatus) }
                do {
                    try cancelled.check()
                    try process.run()
                    onStarted()
                    if cancelled.isCancelled == true { process.terminate() }
                }
                catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
            }
            let result = try await Output(status: status, stdout: output, stderr: errors)
            try cancelled.check()
            return result
        } onCancel: {
            cancelled.cancel()
            if process.isRunning == true { process.terminate() }
        }
    }
}
