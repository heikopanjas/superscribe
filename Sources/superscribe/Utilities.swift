import ArgumentParser
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

func formatBytes(_ bytes: Int64) -> String {
    ByteFormatting.format(bytes)
}

func defaultIntermediateOutputPath(backend: Backend, explicitOutput: String) -> String {
    if explicitOutput.isEmpty == true {
        return "transcript.superscribe.\(backend.rawValue).json"
    }
    return explicitOutput
}

func saveIntermediateTranscript(_ transcript: IntermediateTranscript, to path: String) throws {
    let data = try IntermediateTranscript.jsonEncoder().encode(transcript)
    try data.write(to: URL(fileURLWithPath: path))
}

func printTranscribeSummary(transcript: IntermediateTranscript, duration: TimeInterval) {
    let trackCount = transcript.tracks.count
    let segCount = transcript.tracks.reduce(0) { $0 + $1.segments.count }
    FileHandle.standardError.write(
        Data(
            "Transcribed \(segCount) segments from \(trackCount) track(s) in \(formatDuration(duration))\n"
                .utf8
        )
    )
}

func clearProgressLine() {
    FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
}

func printErr(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

/// Throws when more than one `(name, active)` verb pair is `true`.
func assertMutuallyExclusive(_ verbs: [(String, Bool)]) throws {
    let active = verbs.filter(\.1).map(\.0)
    if active.count > 1 {
        throw ValidationError(
            "Only one of \(active.joined(separator: ", ")) may be used at once."
        )
    }
}

/// Reads `[y/N]` from stdin unless `skip` is true.
func confirm(prompt: String, skip: Bool) -> Bool {
    if skip == true { return true }
    printErr(prompt)
    let answer = readLine(strippingNewline: true)?.lowercased() ?? ""
    return answer == "y" || answer == "yes"
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
    private let throttle: TimeInterval = ProgressReporting.throttleInterval

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

func formatDate(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return f.string(from: date)
}

func formatAge(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    if s < 60 { return "< 1m ago" }
    if s < 3600 { return "\(s / 60)m ago" }
    if s < 86400 {
        let h = s / 3600
        let m = (s % 3600) / 60
        return m > 0 ? "\(h)h \(m)m ago" : "\(h)h ago"
    }
    let d = s / 86400
    let h = (s % 86400) / 3600
    return h > 0 ? "\(d)d \(h)h ago" : "\(d)d ago"
}

extension String {
    func leftPad(toLength length: Int) -> String {
        if count >= length { return String(suffix(length)) }
        return String(repeating: " ", count: length - count) + self
    }

    func rightPad(toLength length: Int) -> String {
        if count >= length { return String(prefix(length)) }
        return self + String(repeating: " ", count: length - count)
    }
}
