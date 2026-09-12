import AVFoundation
import Foundation

/// File-backed mono PCM. Temporary files are removed when the last owner releases them.
public final class PreparedAudio: Sendable {
    public let url: URL
    public let format: AudioFormat
    public let frameCount: Int64
    private let temporary: Bool

    internal init(url: URL, format: AudioFormat, temporary: Bool) throws {
        try AudioValidation.validate(format)
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == Double(format.sampleRate), file.processingFormat.channelCount == 1,
            file.processingFormat.commonFormat == .pcmFormatFloat32
        else { throw AudioPreparerError.unsupportedFormat(url) }
        self.url = url
        self.format = format
        self.frameCount = file.length
        self.temporary = temporary
    }

    deinit {
        if self.temporary == true { try? FileManager.default.removeItem(at: self.url) }
    }

    /// Opens an independent reader so active segment jobs never share a file cursor.
    public func samples(in segment: SpeechSegment) throws -> [Float] {
        let range = try AudioValidation.sliceRange(segment: segment, sampleRate: self.format.sampleRate, count: Int(self.frameCount))
        if range.isEmpty == true { return [] }
        let file = try AVAudioFile(forReading: self.url)
        file.framePosition = Int64(range.lowerBound)
        let count = try AudioValidation.frameCount(Double(range.count))
        let buffer = try AudioBuffers.make(format: file.processingFormat, frames: count)
        let channel = try AudioBuffers.channels(buffer)[0]
        try AudioFileReading.read(file, into: buffer, count: count)

        return Array(UnsafeBufferPointer(start: channel, count: range.count))
    }
}
