import AVFoundation
import Foundation

/// Pulls finite input, reports end of stream, and drains every converted output buffer.
internal enum StreamingAudioConverter {
    internal static let chunkFrames: AVAudioFrameCount = 16_384

    internal static func convert(
        from source: AVAudioFormat,
        to target: AVAudioFormat,
        checkCancellation: () throws -> Void = {},
        read: @escaping (AVAudioFrameCount) throws -> AVAudioPCMBuffer?,
        emit: (AVAudioPCMBuffer) throws -> Void
    ) throws -> Void {
        guard source.sampleRate.isFinite == true, source.sampleRate > 0, source.channelCount > 0,
            target.sampleRate.isFinite == true, target.sampleRate > 0, target.channelCount == 1,
            let converter = AVAudioConverter(from: source, to: target)
        else { throw AudioPreparerError.conversionFailed("Invalid audio format or converter allocation") }
        let output = try AudioBuffers.make(format: target, frames: Self.chunkFrames)
        nonisolated(unsafe) var failure: (any Error)?
        nonisolated(unsafe) let reader = read
        let dependencies = SuperscribeKitTestHooks.testState
        let input: AVAudioConverterInputBlock = { requested, status in
            return SuperscribeKitTestHooks.$testState.withValue(dependencies) {
                do {
                    if let buffer = try reader(requested) {
                        status.pointee = .haveData
                        return buffer
                    }
                }
                catch {
                    failure = error
                }
                status.pointee = .endOfStream
                return nil
            }
        }
        while true {
            try checkCancellation()
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error, withInputFrom: input)
            if let failure { throw failure }
            if status == .error || SuperscribeKitTestHooks.audioConverterErrorWithoutDetails == true {
                throw AudioPreparerError.conversionFailed(error?.localizedDescription ?? "The audio converter failed without diagnostic details")
            }
            if output.frameLength > 0 { try emit(output) }
            if status == .endOfStream { break }
        }
        return
    }

    internal static func convert(
        file: AVAudioFile, to target: AVAudioFormat,
        checkCancellation: () throws -> Void = {},
        emit: (AVAudioPCMBuffer) throws -> Void
    ) throws -> Void {
        let input = try AudioBuffers.make(format: file.processingFormat, frames: Self.chunkFrames)
        try Self.convert(
            from: file.processingFormat, to: target, checkCancellation: checkCancellation,
            read: { requested in
                let remaining = file.length - file.framePosition
                if remaining == 0 { return nil }
                if let threshold = SuperscribeKitTestHooks.audioReadFailureAfterFrames, file.framePosition >= threshold {
                    throw CocoaError(.fileReadUnknown)
                }
                let count = min(requested, Self.chunkFrames, AVAudioFrameCount(min(remaining, Int64(Self.chunkFrames))))
                try AudioFileReading.read(file, into: input, count: count)

                return input
            }, emit: emit)
    }

    /// The emitter must copy buffers it retains: streaming buffers are reused.
    internal static func convert(buffer: AVAudioPCMBuffer, to target: AVAudioFormat, emit: (AVAudioPCMBuffer) throws -> Void) throws -> Void {
        let input = try AudioBuffers.make(format: buffer.format, frames: Self.chunkFrames)
        let source = try AudioBuffers.channels(buffer)
        let destination = try AudioBuffers.channels(input)
        var offset: AVAudioFrameCount = 0
        try Self.convert(
            from: buffer.format, to: target,
            read: { requested in
                if offset == buffer.frameLength { return nil }
                let count = min(requested, Self.chunkFrames, buffer.frameLength - offset)
                for channel in 0 ..< Int(buffer.format.channelCount) {
                    destination[channel].update(from: source[channel].advanced(by: Int(offset)), count: Int(count))
                }
                input.frameLength = count
                offset += count
                return input
            }, emit: emit)
    }
}
