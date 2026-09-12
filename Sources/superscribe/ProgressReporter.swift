import Foundation
import SuperscribeKit

/// Owns progress ordering and its final drain. State is confined to `queue`.
final class ProgressReporter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "superscribe.progress")
    private let now: @Sendable () -> TimeInterval
    private let write: @Sendable (String) -> Void
    private var last: [String: TimeInterval] = [:]
    private var finished = false

    init(
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        write: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) {
        self.now = now
        self.write = write
    }

    func conversion(_ progress: ConversionProgress) -> Void {
        self.queue.async {
            guard self.finished == false else { return }
            let time = self.now()
            let previous = self.last[progress.source.path] ?? -.infinity
            guard progress.fraction >= 1 || time - previous >= ProgressReporting.throttleInterval else { return }
            self.last[progress.source.path] = time
            self.write("\rConverting \(progress.source.lastPathComponent) [\(Int((progress.fraction * 100).rounded()))%]\u{1B}[K")
        }
    }

    func transcription(_ progress: TranscriptionProgress) -> Void {
        self.queue.async {
            guard self.finished == false else { return }
            self.write("\r[\(progress.speaker)] segment \(progress.segmentIndex)/\(progress.totalSegments) — overall \(progress.overallCompleted)/\(progress.overallTotal)\u{1B}[K")
        }
    }

    func finish() async -> Void {
        await withCheckedContinuation { continuation in
            self.queue.async {
                if self.finished == false {
                    self.finished = true
                    self.write("\r\u{1B}[K")
                }
                continuation.resume()
            }
        }
    }
}
