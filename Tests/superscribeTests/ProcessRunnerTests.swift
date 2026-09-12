import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Subprocess ownership", .serialized, ResetSharedStateTrait())
struct ProcessRunnerTests {
    @Test func drainsDiagnosticsLargerThanPipeCapacity() async throws -> Void {
        let output = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "head -c 1048576 /dev/zero >&2; printf done"])
        #expect(output.status == 0)
        #expect(output.stderr.count == 1_048_576)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "done")
    }

    @Test func cancellationJoinsProcessAndReaders() async -> Void {
        let started = TestSignal()
        let task = Task {
            try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"], onStarted: { started.signal() })
        }
        await started.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func cancellationDuringLaunch() async -> Void {
        let task = Task {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"],
                onStarted: {
                    withUnsafeCurrentTask { $0?.cancel() }
                })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func launchFailureClosesReaders() async -> Void {
        await #expect(throws: (any Error).self) {
            _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/does-not-exist"), arguments: [])
        }
    }
}
