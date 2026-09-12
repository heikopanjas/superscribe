import AVFoundation
import Foundation

internal enum AudioFileReading {
    /// AVAudioFile may return a short read before EOF; continue until the requested frames arrive.
    internal static func read(_ file: AVAudioFile, into buffer: AVAudioPCMBuffer, count: AVAudioFrameCount) throws -> Void {
        try AudioBuffers.dependencies.read(file, buffer, count)
        while buffer.frameLength < count {
            let remaining = count - buffer.frameLength
            let tail = try AudioBuffers.make(format: buffer.format, frames: remaining)
            let destination = try AudioBuffers.channels(buffer)
            try AudioBuffers.dependencies.read(file, tail, remaining)
            guard tail.frameLength > 0 else { throw CocoaError(.fileReadCorruptFile) }
            let source = try AudioBuffers.channels(tail)
            for channel in 0 ..< Int(buffer.format.channelCount) {
                destination[channel].advanced(by: Int(buffer.frameLength)).update(from: source[channel], count: Int(tail.frameLength))
            }
            buffer.frameLength += tail.frameLength
        }
    }
}
