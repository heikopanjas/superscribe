import AVFoundation
import Foundation

/// AVAudioFile state is accessed exclusively on its owned worker, including final cleanup.
internal final class IsolationAudioFile: @unchecked Sendable {
    internal let frameCount: Int64
    internal let vocalsURL: URL
    private let inputURL: URL
    private let directory: URL
    private let worker: BlockingWorker
    private let channels: Int
    private let format: AVAudioFormat
    private var output: AVAudioFile?

    private init(source: URL, sampleRate: Int, channels: Int, worker: BlockingWorker, cancellation: CancellationFlag) throws {
        self.worker = worker
        self.channels = channels
        let format = try AudioBuffers.pcmFormat(AudioFormat(sampleRate: sampleRate, channels: channels))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("superscribe-isolate-\(UUID().uuidString)")
        let inputURL = directory.appendingPathComponent("input.wav")
        self.format = format
        self.directory = directory
        self.inputURL = inputURL
        self.vocalsURL = directory.appendingPathComponent("vocals.wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try autoreleasepool {
                let sourceFile = try AVAudioFile(forReading: source)
                let destination = try AVAudioFile(forWriting: inputURL, settings: AudioBuffers.fileSettings(for: format), commonFormat: .pcmFormatFloat32, interleaved: false)
                try StreamingAudioConverter.convert(file: sourceFile, to: format, checkCancellation: cancellation.check) { try destination.write(from: $0) }
            }
            self.frameCount = try AVAudioFile(forReading: self.inputURL).length
            let mono = try AudioBuffers.format(AudioFormat(sampleRate: sampleRate, channels: 1))
            self.output = try AVAudioFile(forWriting: self.vocalsURL, settings: AudioBuffers.fileSettings(for: mono), commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        catch {
            try? FileManager.default.removeItem(at: self.directory)
            throw error
        }
    }

    internal static func open(source: URL, sampleRate: Int, channels: Int) async throws -> IsolationAudioFile {
        let worker = BlockingWorker(label: "superscribe.isolation.io")
        let buffers = AudioBuffers.dependencies
        let hooks = SuperscribeKitTestHooks.testState
        return try await worker.run { cancellation in
            return try AudioBuffers.$dependencies.withValue(buffers) {
                return try SuperscribeKitTestHooks.$testState.withValue(hooks) {
                    return try IsolationAudioFile(source: source, sampleRate: sampleRate, channels: channels, worker: worker, cancellation: cancellation)
                }
            }
        }
    }

    internal func read(start: Int64, count: Int) async throws -> [Float] {
        let buffers = AudioBuffers.dependencies
        return try await self.worker.run { _ in
            return try AudioBuffers.$dependencies.withValue(buffers) {
                let file = try AVAudioFile(forReading: self.inputURL)
                file.framePosition = start
                let buffer = try AudioBuffers.make(format: self.format, frames: AVAudioFrameCount(count))
                try AudioFileReading.read(file, into: buffer, count: AVAudioFrameCount(count))
                let channels = try AudioBuffers.channels(buffer)
                let padded = max(2, count)
                var samples = [Float](repeating: 0, count: padded * self.channels)
                for channel in 0 ..< self.channels {
                    samples.withUnsafeMutableBufferPointer { destination in
                        destination.baseAddress?.advanced(by: channel * padded).update(from: channels[channel], count: count)
                    }
                }
                return samples
            }
        }
    }

    internal func write(_ samples: [Float]) async throws -> Void {
        let buffers = AudioBuffers.dependencies
        try await self.worker.run { _ in
            return try AudioBuffers.$dependencies.withValue(buffers) {
                guard let output = self.output else { throw InputValidationError("Isolation output is already closed") }
                let buffer = try AudioBuffers.make(format: output.processingFormat, frames: AVAudioFrameCount(samples.count))
                buffer.frameLength = AVAudioFrameCount(samples.count)
                let channel = try AudioBuffers.channels(buffer)[0]
                samples.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
                }
                try output.write(from: buffer)
            }
        }
    }

    internal func close() async throws -> Void {
        try await self.worker.run { _ in self.output = nil }
    }

    deinit {
        self.worker.sync {
            self.output = nil
            try? FileManager.default.removeItem(at: self.directory)
        }
    }
}
