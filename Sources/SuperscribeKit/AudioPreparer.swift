import AVFoundation
import Foundation

/// Errors raised by `AudioPreparer`.
public enum AudioPreparerError: Error, CustomStringConvertible {
    case cannotReadFile(URL, underlying: Error)
    case unsupportedFormat(URL)
    case conversionFailed(String)

    public var description: String {
        switch self {
            case .cannotReadFile(let url, let err):
                return "Cannot read audio/video file \(url.path): \(err)"
            case .unsupportedFormat(let url):
                return "Unsupported media format: \(url.path)"
            case .conversionFailed(let msg):
                return "Audio conversion failed: \(msg)"
        }
    }
}

/// Progress update emitted while `AudioPreparer` is converting a file.
public struct ConversionProgress: Sendable {
    /// Source file being converted.
    public let source: URL
    /// Source frames processed so far.
    public let framesProcessed: Int64
    /// Total source frames in the file (0 if unknown).
    public let framesTotal: Int64
    /// 0…1 fraction. 1.0 once the file has been fully consumed.
    public let fraction: Double
}

/// Reads any audio or video file that AVFoundation can handle and
/// converts it to the PCM format a backend requires.
///
/// This is independent of any concrete backend — it queries
/// `BackendCapabilities.requiredAudioFormat` to decide the target
/// sample rate and channel count.
public struct AudioPreparer: Sendable {
    public let targetFormat: AudioFormat
    public let cache: ConvertedAudioCache?

    public init(for capabilities: BackendCapabilities, cache: ConvertedAudioCache? = nil) {
        self.targetFormat = capabilities.requiredAudioFormat
        self.cache = cache
    }

    public init(targetFormat: AudioFormat, cache: ConvertedAudioCache? = nil) {
        self.targetFormat = targetFormat
        self.cache = cache
    }

    /// Read the entire file and return PCM Float32 samples in the
    /// target format.
    public func loadAndConvert(url: URL) throws -> [Float] {
        try loadAndConvert(url: url, onProgress: nil)
    }

    /// Read the entire file and return PCM Float32 samples in the
    /// target format, optionally reporting conversion progress.
    ///
    /// Progress is reported in terms of source frames consumed and is
    /// only emitted when an actual sample-rate/channel/format conversion
    /// is required. The fast path (source already matches the target
    /// format) skips conversion entirely and emits a single 1.0 tick on
    /// completion.
    public func loadAndConvert(
        url: URL,
        onProgress: (@Sendable (ConversionProgress) -> Void)?
    ) throws -> [Float] {
        // Check the on-disk cache first. A hit reads the cached WAV via
        // the fast path (it is already in the target format).
        let cacheKey = cache?.key(for: url, targetFormat: targetFormat)
        if let cache, let key = cacheKey, let cached = cache.lookup(key) {
            return try loadCached(at: cached, originalURL: url, onProgress: onProgress)
        }

        let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(targetFormat.sampleRate),
            channels: AVAudioChannelCount(targetFormat.channels),
            interleaved: false
        )!

        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: url)
        }
        catch {
            throw AudioPreparerError.cannotReadFile(url, underlying: error)
        }

        let sourceFormat = sourceFile.processingFormat
        let sourceLength = AVAudioFrameCount(sourceFile.length)

        let samples: [Float]

        // Fast path: source already matches target.
        if Int(sourceFormat.sampleRate) == targetFormat.sampleRate,
            sourceFormat.channelCount == AVAudioChannelCount(targetFormat.channels),
            sourceFormat.commonFormat == .pcmFormatFloat32
        {
            let buffer: AVAudioPCMBuffer? =
                if SuperscribeKitTestHooks.forceAudioPreparerFastPathBufferFailure == true {
                    nil
                }
                else {
                    AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceLength)
                }
            guard let buffer else {
                throw AudioPreparerError.conversionFailed("Cannot allocate source buffer")
            }
            try sourceFile.read(into: buffer)
            onProgress?(
                ConversionProgress(
                    source: url,
                    framesProcessed: Int64(buffer.frameLength),
                    framesTotal: Int64(sourceLength),
                    fraction: 1.0
                )
            )
            samples = Array(
                UnsafeBufferPointer(
                    start: buffer.floatChannelData![0],
                    count: Int(buffer.frameLength)
                ))
        }
        else {
            // Streaming convert: read the source in chunks, feed each chunk
            // to the converter, append the converted frames, report progress.
            samples = try convert(
                sourceFile: sourceFile,
                to: avFormat,
                sourceURL: url,
                onProgress: onProgress
            )
        }

        // Best-effort cache write; failures are non-fatal.
        if let cache, let key = cacheKey {
            do {
                _ = try cache.store(samples: samples, format: targetFormat, key: key)
            }
            catch {
                FileHandle.standardError.write(
                    Data(
                        "warning: could not cache converted audio for \(url.lastPathComponent): \(error)\n"
                            .utf8
                    )
                )
            }
        }

        return samples
    }

    /// Read a previously cached WAV that already matches the target format.
    private func loadCached(
        at cached: URL,
        originalURL: URL,
        onProgress: (@Sendable (ConversionProgress) -> Void)?
    ) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: cached)
        }
        catch {
            throw AudioPreparerError.cannotReadFile(cached, underlying: error)
        }
        let length = AVAudioFrameCount(file.length)
        let buffer: AVAudioPCMBuffer? =
            if SuperscribeKitTestHooks.forceAudioPreparerCachedBufferFailure == true {
                nil
            }
            else {
                AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: length)
            }
        guard let buffer else {
            throw AudioPreparerError.conversionFailed("Cannot allocate cached read buffer")
        }
        try file.read(into: buffer)
        onProgress?(
            ConversionProgress(
                source: originalURL,
                framesProcessed: Int64(buffer.frameLength),
                framesTotal: Int64(length),
                fraction: 1.0
            )
        )
        return Array(
            UnsafeBufferPointer(
                start: buffer.floatChannelData![0],
                count: Int(buffer.frameLength)
            ))
    }

    /// Slice already-loaded samples for a speech segment.
    public func slice(
        _ samples: [Float],
        segment: SpeechSegment
    ) -> [Float] {
        let startSample = max(0, Int(segment.start * Double(targetFormat.sampleRate)))
        let endSample = min(samples.count, Int(segment.end * Double(targetFormat.sampleRate)))
        guard startSample < endSample else { return [] }
        return Array(samples[startSample ..< endSample])
    }

    // MARK: - Private

    /// Approx. 1 second of source audio per chunk. Tuning this affects
    /// progress granularity and converter overhead, not correctness.
    private static let chunkFrames: AVAudioFrameCount = 48_000

    private func convert(
        sourceFile: AVAudioFile,
        to targetAVFormat: AVAudioFormat,
        sourceURL: URL,
        onProgress: (@Sendable (ConversionProgress) -> Void)?
    ) throws -> [Float] {
        let sourceFormat = sourceFile.processingFormat
        let sourceLength = sourceFile.length  // Int64

        let converter: AVAudioConverter? =
            if SuperscribeKitTestHooks.forceAudioPreparerConverterCreationFailure == true {
                nil
            }
            else {
                AVAudioConverter(from: sourceFormat, to: targetAVFormat)
            }
        guard let converter else {
            throw AudioPreparerError.conversionFailed(
                "Cannot create converter from \(sourceFormat) to \(targetAVFormat)"
            )
        }

        let ratio = targetAVFormat.sampleRate / sourceFormat.sampleRate

        // Per-chunk output capacity, with a small safety margin to absorb
        // any internal latency/overshoot.
        let outputChunkCapacity =
            AVAudioFrameCount(Double(Self.chunkFrames) * ratio) + 1_024

        let outputBuffer: AVAudioPCMBuffer? =
            if SuperscribeKitTestHooks.forceAudioPreparerOutputBufferFailure == true {
                nil
            }
            else {
                AVAudioPCMBuffer(pcmFormat: targetAVFormat, frameCapacity: outputChunkCapacity)
            }
        guard let outputBuffer else {
            throw AudioPreparerError.conversionFailed("Cannot allocate output buffer")
        }

        // Pre-size the result around the expected total length to avoid
        // repeated reallocations on long files.
        var result: [Float] = []
        result.reserveCapacity(Int(Double(sourceLength) * ratio) + 1_024)

        // Reusable input buffer.
        let inputChunk: AVAudioPCMBuffer? =
            if SuperscribeKitTestHooks.forceAudioPreparerInputBufferFailure == true {
                nil
            }
            else {
                AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: Self.chunkFrames)
            }
        guard let inputChunk else {
            throw AudioPreparerError.conversionFailed("Cannot allocate input buffer")
        }

        // Streaming feeder state. The converter pulls chunks via the
        // input block; we read one source chunk per pull and report
        // progress against `framesProcessedTotal`. `AVAudioPCMBuffer` is
        // not `Sendable`, so the reused chunk needs the unsafe wrapper.
        nonisolated(unsafe) let unsafeChunk = inputChunk
        nonisolated(unsafe) var framesProcessedTotal: Int64 = 0
        nonisolated(unsafe) var endOfStream = false

        nonisolated(unsafe) var inputPulls = 0
        let inputBlock: AVAudioConverterInputBlock = { _, statusOut in
            if SuperscribeKitTestHooks.forceAudioPreparerEndOfStreamImmediately == true {
                statusOut.pointee = .endOfStream
                return nil
            }
            if endOfStream == true {
                statusOut.pointee = .endOfStream
                return nil
            }
            inputPulls += 1
            if SuperscribeKitTestHooks.forceAudioPreparerSecondPullEndOfStream == true,
                inputPulls > 1
            {
                endOfStream = true
                statusOut.pointee = .endOfStream
                return nil
            }
            do {
                try sourceFile.read(into: unsafeChunk, frameCount: Self.chunkFrames)
            }
            catch {
                statusOut.pointee = .endOfStream
                return nil
            }
            if SuperscribeKitTestHooks.forceAudioPreparerZeroFrameRead == true {
                unsafeChunk.frameLength = 0
            }
            if unsafeChunk.frameLength == 0 {
                endOfStream = true
                statusOut.pointee = .endOfStream
                return nil
            }
            framesProcessedTotal += Int64(unsafeChunk.frameLength)
            if SuperscribeKitTestHooks.forceAudioPreparerMarkEndBeforeSecondPull == true,
                inputPulls == 1
            {
                endOfStream = true
            }
            statusOut.pointee = .haveData
            return unsafeChunk
        }

        // Drive the converter until the input is fully drained.
        while true {
            outputBuffer.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError,
                withInputFrom: inputBlock
            )

            if let forced = SuperscribeKitTestHooks.forceAudioPreparerConversionError {
                throw AudioPreparerError.conversionFailed(forced)
            }

            var effectiveStatus = status
            var effectiveError = conversionError
            if SuperscribeKitTestHooks.forceAudioPreparerConverterNativeError == true {
                effectiveStatus = .error
                effectiveError =
                    effectiveError
                    ?? NSError(
                        domain: "SuperscribeKitTestHooks",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "forced conversion error"]
                    )
            }

            if effectiveStatus == .error, let err = effectiveError {
                throw AudioPreparerError.conversionFailed(err.localizedDescription)
            }

            if SuperscribeKitTestHooks.forceAudioPreparerSecondPullEndOfStream == true,
                endOfStream == true, outputBuffer.frameLength == 0
            {
                break
            }

            if outputBuffer.frameLength > 0,
                let channelData = outputBuffer.floatChannelData
            {
                let count = Int(outputBuffer.frameLength)
                result.append(
                    contentsOf: UnsafeBufferPointer(start: channelData[0], count: count)
                )
            }

            if let onProgress, sourceLength > 0 {
                let processed = min(framesProcessedTotal, sourceLength)
                let fraction =
                    sourceLength > 0
                    ? min(1.0, Double(processed) / Double(sourceLength)) : 0
                onProgress(
                    ConversionProgress(
                        source: sourceURL,
                        framesProcessed: processed,
                        framesTotal: sourceLength,
                        fraction: fraction
                    )
                )
            }

            if status == .endOfStream || (endOfStream == true && outputBuffer.frameLength == 0) {
                break
            }
        }

        // Final 1.0 tick in case the loop ended before reaching it.
        if let onProgress, sourceLength > 0 {
            onProgress(
                ConversionProgress(
                    source: sourceURL,
                    framesProcessed: sourceLength,
                    framesTotal: sourceLength,
                    fraction: 1.0
                )
            )
        }

        return result
    }
}
