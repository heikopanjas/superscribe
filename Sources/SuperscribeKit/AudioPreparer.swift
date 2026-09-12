import AVFoundation
import Foundation

/// Converts audio with bounded buffers; whole-array loading is an explicit convenience API.
public struct AudioPreparer: Sendable {
    public let targetFormat: AudioFormat
    public let cache: ConvertedAudioCache?

    public init(for capabilities: BackendCapabilities, cache: ConvertedAudioCache? = nil) {
        self.init(targetFormat: capabilities.requiredAudioFormat, cache: cache)
    }

    public init(targetFormat: AudioFormat, cache: ConvertedAudioCache? = nil) {
        self.targetFormat = targetFormat
        self.cache = cache
    }

    public func loadAndConvert(url: URL, onProgress: (@Sendable (ConversionProgress) -> Void)? = nil) throws -> [Float] {
        let prepared = try self.prepare(url: url, onProgress: onProgress)
        return try prepared.samples(in: SpeechSegment(start: 0, end: Double(prepared.frameCount) / Double(self.targetFormat.sampleRate)))
    }

    public func slice(_ samples: [Float], segment: SpeechSegment) throws -> [Float] {
        try AudioValidation.validate(self.targetFormat)
        return Array(samples[try AudioValidation.sliceRange(segment: segment, sampleRate: self.targetFormat.sampleRate, count: samples.count)])
    }

    /// A persistent cache hit is reused; otherwise conversion is staged beside its destination.
    public func prepare(
        url: URL, onProgress: (@Sendable (ConversionProgress) -> Void)? = nil,
        checkCancellation: () throws -> Void = {}
    ) throws -> PreparedAudio {
        do { return try self.prepareCached(url: url, onProgress: onProgress, checkCancellation: checkCancellation) }
        catch {
            guard self.cache != nil else { throw error }
            try checkCancellation()
            return try AudioPreparer(targetFormat: self.targetFormat).prepare(url: url, onProgress: onProgress, checkCancellation: checkCancellation)
        }
    }

    private func prepareCached(url: URL, onProgress: (@Sendable (ConversionProgress) -> Void)?, checkCancellation: () throws -> Void) throws -> PreparedAudio {
        try AudioValidation.validate(self.targetFormat)
        try checkCancellation()
        let key = self.cache?.key(for: url, targetFormat: self.targetFormat)
        if let cache = self.cache, let key, let cached = cache.lookup(key) {
            do {
                let prepared = try PreparedAudio(url: cached, format: self.targetFormat, temporary: false)
                // Verify the tail is readable before trusting a cached container's advertised length.
                _ = try prepared.samples(
                    in: SpeechSegment(
                        start: max(0, Double(prepared.frameCount - 1) / Double(self.targetFormat.sampleRate)), end: Double(prepared.frameCount) / Double(self.targetFormat.sampleRate)))
                onProgress?(ConversionProgress(source: url, framesProcessed: prepared.frameCount, framesTotal: prepared.frameCount, fraction: 1))
                return prepared
            }
            catch {
                try? FileManager.default.removeItem(at: cached)
                try? cache.updateManifest(removingDigest: key.digest)
            }
        }
        let destination: URL
        if let cache = self.cache, let key {
            try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
            destination = cache.cacheURL(for: key)
        }
        else {
            destination = FileManager.default.temporaryDirectory.appendingPathComponent("superscribe-\(UUID().uuidString).wav")
        }
        let staging = SuperscribeFS.stagingURL(beside: destination, label: "audio").appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: staging) }
        let frames = try autoreleasepool {
            return try self.convert(url: url, to: staging, onProgress: onProgress, checkCancellation: checkCancellation)
        }
        try checkCancellation()
        try SuperscribeFS.atomicReplace(staging: staging, final: destination, policy: .replaceExisting)
        if let cache = self.cache, let key {
            try cache.updateManifest(adding: .init(digest: key.digest, sourcePath: key.sourcePath, storedAt: Date()))
        }
        let prepared = try PreparedAudio(url: destination, format: self.targetFormat, temporary: key == nil)
        onProgress?(ConversionProgress(source: url, framesProcessed: frames, framesTotal: frames, fraction: 1))
        return prepared
    }

    /// Returning from this scope closes the WAV writer before publication.
    @inline(never)
    private func convert(
        url: URL, to destination: URL, onProgress: (@Sendable (ConversionProgress) -> Void)?, checkCancellation: () throws -> Void
    ) throws -> Int64 {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { throw AudioPreparerError.cannotReadFile(url, underlying: error) }
        let format = try AudioBuffers.format(self.targetFormat)
        let output = try AVAudioFile(forWriting: destination, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try StreamingAudioConverter.convert(file: file, to: format, checkCancellation: checkCancellation) { buffer in
            try output.write(from: buffer)
            if file.length > 0, file.framePosition < file.length {
                onProgress?(ConversionProgress(source: url, framesProcessed: file.framePosition, framesTotal: file.length, fraction: Double(file.framePosition) / Double(file.length)))
            }
        }
        return file.length
    }
}
