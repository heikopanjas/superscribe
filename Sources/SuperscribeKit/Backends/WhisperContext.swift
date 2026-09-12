import Foundation
import whisper

/// Sendable box for a C `OpaquePointer` (whisper_context *).
/// Context access is exclusive to its owning backend; per-call state does not
/// make concurrent use of a shared context safe.
internal final class WhisperContext: @unchecked Sendable {
    let ptr: OpaquePointer
    private let manageLifetime: Bool
    private let worker: BlockingWorker
    private let liveDependencies: TestDependencyStorage<WhisperLiveAPI.TestState>

    init(_ ptr: OpaquePointer, worker: BlockingWorker, manageLifetime: Bool = true) {
        self.ptr = ptr
        self.manageLifetime = manageLifetime
        self.worker = worker
        self.liveDependencies = WhisperLiveAPI.testState
    }

    /// Unit-test placeholder; never passed to whisper C API release functions.
    static func testStub(worker: BlockingWorker) -> WhisperContext {
        return WhisperContext(OpaquePointer(Unmanaged.passUnretained(worker).toOpaque()), worker: worker, manageLifetime: false)
    }

    deinit {
        if self.manageLifetime == true {
            self.worker.sync {
                WhisperLiveAPI.$testState.withValue(self.liveDependencies) {
                    WhisperLiveAPI.releaseContext(self.ptr)
                }
            }
        }
    }
}
