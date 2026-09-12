import ArgumentParser
import Foundation
import SuperscribeKit

// MARK: - Progress helpers

func formatBytes(_ bytes: Int64) -> String {
    return ByteFormatting.format(bytes)
}

func defaultIntermediateOutputPath(backend: Backend, explicitOutput: String) -> String {
    if explicitOutput.isEmpty == true {
        return "transcript.superscribe.\(backend.rawValue).json"
    }
    return explicitOutput
}

func saveIntermediateTranscript(_ transcript: IntermediateTranscript, to path: String) throws -> Void {
    let data = try IntermediateTranscript.jsonEncoder().encode(transcript)
    try data.write(to: URL(fileURLWithPath: path))
}

func printTranscribeSummary(transcript: IntermediateTranscript, duration: TimeInterval) -> Void {
    let trackCount = transcript.tracks.count
    let segCount = transcript.tracks.reduce(0) { $0 + $1.segments.count }
    FileHandle.standardError.write(
        Data(
            "Transcribed \(segCount) segments from \(trackCount) track(s) in \(formatDuration(duration))\n"
                .utf8
        )
    )
}

func clearProgressLine() -> Void {
    FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
}

func printErr(_ text: String) -> Void {
    FileHandle.standardError.write(Data(text.utf8))
}

/// Throws when more than one `(name, active)` verb pair is `true`.
func assertMutuallyExclusive(_ verbs: [(String, Bool)]) throws -> Void {
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
        return if m > 0 { "\(h)h \(m)m ago" }
        else { "\(h)h ago" }
    }
    let d = s / 86400
    let h = (s % 86400) / 3600
    return if h > 0 { "\(d)d \(h)h ago" }
    else { "\(d)d ago" }
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
