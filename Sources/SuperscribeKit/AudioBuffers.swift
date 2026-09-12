import AVFoundation
import Foundation

internal enum AudioBuffers {
    internal struct Dependencies: Sendable {
        internal var read: @Sendable (AVAudioFile, AVAudioPCMBuffer, AVAudioFrameCount) throws -> Void = { try $0.read(into: $1, frameCount: $2) }
        internal var allocate: @Sendable (AVAudioFormat, AVAudioFrameCount) -> AVAudioPCMBuffer? = { AVAudioPCMBuffer(pcmFormat: $0, frameCapacity: $1) }
        internal var format: @Sendable (AudioFormat) -> AVAudioFormat? = {
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double($0.sampleRate), channels: AVAudioChannelCount($0.channels), interleaved: false)
        }
    }
    @TaskLocal internal static var dependencies = Dependencies()

    internal static func make(format: AVAudioFormat, frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = Self.dependencies.allocate(format, frames) else { throw AudioPreparerError.conversionFailed("Cannot allocate audio buffer") }
        return buffer
    }

    internal static func format(_ format: AudioFormat) throws -> AVAudioFormat {
        try AudioValidation.validate(format)
        guard let result = Self.dependencies.format(format) else { throw AudioPreparerError.conversionFailed("Cannot construct audio format") }
        return result
    }

    internal static func channels(_ buffer: AVAudioPCMBuffer) throws -> UnsafePointer<UnsafeMutablePointer<Float>> {
        guard let channels = buffer.floatChannelData else { throw AudioPreparerError.conversionFailed("Expected Float32 audio samples") }
        return channels
    }
}
