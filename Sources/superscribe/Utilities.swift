import Foundation
import SuperscribeKit

// MARK: - Progress helpers

let progressQueue = DispatchQueue(label: "superscribe.progress", qos: .utility)

func makeProgressHandler() -> @Sendable (TranscriptionProgress) -> Void {
    { progress in
        let pct = Int(Double(progress.overallCompleted) / Double(max(1, progress.overallTotal)) * 100)
        let line =
            "\r[\(progress.speaker)] segment \(progress.segmentIndex)/\(progress.totalSegments)  —  overall \(progress.overallCompleted)/\(progress.overallTotal) (\(pct)%)"
        let data = Data((line + "  ").utf8)
        progressQueue.async { FileHandle.standardError.write(data) }
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return String(format: "%.1fs", seconds)
    }
    let m = Int(seconds) / 60
    let s = seconds - Double(m * 60)
    return String(format: "%dm %04.1fs", m, s)
}

/// Throttled per-track stderr progress reporter for audio conversion.
/// Emits at most ~10 updates per second per track and a final 100% line.
final class ConversionProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmitted: [String: Date] = [:]
    private var lastFraction: [String: Double] = [:]
    private let throttle: TimeInterval = 0.1

    func handler() -> @Sendable (ConversionProgress) -> Void {
        { [weak self] progress in
            self?.handle(progress)
        }
    }

    private func handle(_ progress: ConversionProgress) {
        let key = progress.source.path
        let now = Date()
        var shouldEmit = false
        var isFinal = false
        lock.lock()
        let last = lastEmitted[key]
        let prevFraction = lastFraction[key] ?? -1
        isFinal = progress.fraction >= 1.0 && prevFraction < 1.0
        if isFinal == true || last == nil || now.timeIntervalSince(last!) >= throttle {
            lastEmitted[key] = now
            lastFraction[key] = progress.fraction
            shouldEmit = true
        }
        lock.unlock()
        guard shouldEmit == true else { return }

        let pct = Int((progress.fraction * 100).rounded())
        let name = progress.source.lastPathComponent
        let suffix = isFinal ? "\n" : ""
        let line = "\rConverting \(name) [\(pct)%]\u{1B}[K\(suffix)"
        progressQueue.async { FileHandle.standardError.write(Data(line.utf8)) }
    }
}

// MARK: - Formatting helpers

func formatBytes(_ bytes: Int64) -> String {
    let units: [(threshold: Double, suffix: String)] = [
        (1024 * 1024 * 1024, "GiB"),
        (1024 * 1024, "MiB"),
        (1024, "KiB")
    ]
    let value = Double(bytes)
    for (threshold, suffix) in units where value >= threshold {
        return String(format: "%.1f %@", value / threshold, suffix)
    }
    return "\(bytes) B"
}

func formatDate(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return f.string(from: date)
}

extension String {
    func leftPad(toLength length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
