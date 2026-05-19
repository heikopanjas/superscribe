import AVFoundation
import CryptoKit
import Foundation

/// On-disk cache of audio that has already been converted into a backend's
/// required PCM format. Keyed by source identity (path + size + mtime) plus
/// a stable description of the target format, so re-running transcription
/// on the same input file skips re-conversion.
///
/// Default location: `~/.cache/superscribe/audio/<sha256>.wav`.
public struct ConvertedAudioCache: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
    }

    public static func defaultRoot() -> URL {
        SuperscribePaths.audioCacheRoot()
    }

    /// Identity of a (source file, target format) pair.
    public struct CacheKey: Sendable, Hashable {
        public let sourcePath: String
        public let sourceSize: Int64
        public let sourceMtimeNanos: Int64
        public let formatKey: String

        public init(
            sourcePath: String,
            sourceSize: Int64,
            sourceMtimeNanos: Int64,
            formatKey: String
        ) {
            self.sourcePath = sourcePath
            self.sourceSize = sourceSize
            self.sourceMtimeNanos = sourceMtimeNanos
            self.formatKey = formatKey
        }

        /// Stable digest used as the on-disk filename stem.
        public var digest: String {
            let raw =
                "\(sourcePath)|\(sourceSize)|\(sourceMtimeNanos)|\(formatKey)"
            let bytes = SHA256.hash(data: Data(raw.utf8))
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Build a cache key from a source file URL and a target audio format.
    /// Returns `nil` if the file's size or mtime cannot be read.
    public func key(for url: URL, targetFormat: AudioFormat) -> CacheKey? {
        if SuperscribeKitTestHooks.forceCacheKeyAttributeParseFailure == true {
            return nil
        }
        let absolute = url.standardizedFileURL.path
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: absolute)
        }
        catch {
            return nil
        }
        guard
            SuperscribeKitTestHooks.forceCacheKeyAttributeGuardFailure == false,
            let size = (attrs[.size] as? NSNumber)?.int64Value,
            let modDate = attrs[.modificationDate] as? Date
        else {
            return nil
        }
        let mtimeNanos = Int64(modDate.timeIntervalSince1970 * 1_000_000_000)
        return CacheKey(
            sourcePath: absolute,
            sourceSize: size,
            sourceMtimeNanos: mtimeNanos,
            formatKey: Self.formatKey(for: targetFormat)
        )
    }

    /// Stable, human-readable description of the target PCM format.
    public static func formatKey(for format: AudioFormat) -> String {
        "f32-\(format.sampleRate)-\(format.channels)"
    }

    /// On-disk URL for a cache key (whether or not the file exists).
    public func cacheURL(for key: CacheKey) -> URL {
        root.appendingPathComponent("\(key.digest).wav", isDirectory: false)
    }

    /// Returns the cache URL if a file is present at that location.
    public func lookup(_ key: CacheKey) -> URL? {
        let url = cacheURL(for: key)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Manifest

    /// Records the origin of a cache entry so `superscribe cache --list` can
    /// display source filenames instead of raw SHA256 digests.
    public struct ManifestEntry: Codable, Sendable {
        public let digest: String
        public let sourcePath: String
        public let storedAt: Date
    }

    /// URL of the manifest sidecar file (`manifest.json` in the cache root).
    public var manifestURL: URL {
        root.appendingPathComponent("manifest.json", isDirectory: false)
    }

    /// Load the manifest from disk. Returns an empty dictionary when no manifest exists.
    public func loadManifest() throws -> [String: ManifestEntry] {
        guard FileManager.default.fileExists(atPath: manifestURL.path) == true else { return [:] }
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONCoding.catalogDecoder()
        let entries = try decoder.decode([ManifestEntry].self, from: data)
        return Dictionary(entries.map { ($0.digest, $0) }, uniquingKeysWith: { $1 })
    }

    /// Upsert an entry in the manifest. Callers treat failures as non-fatal.
    public func updateManifest(adding entry: ManifestEntry) throws {
        var current = (try? loadManifest()) ?? [:]
        current[entry.digest] = entry
        try writeManifest(Array(current.values))
    }

    /// Remove an entry from the manifest. No-op if the digest is absent.
    public func updateManifest(removingDigest digest: String) throws {
        var current = (try? loadManifest()) ?? [:]
        guard current[digest] != nil else { return }
        current.removeValue(forKey: digest)
        try writeManifest(Array(current.values))
    }

    private func writeManifest(_ entries: [ManifestEntry]) throws {
        let data = try JSONCoding.catalogEncoder().encode(entries)
        let stagingURL = SuperscribeFS.stagingURL(beside: manifestURL, label: "manifest.json")
        try data.write(to: stagingURL)
        try SuperscribeFS.atomicReplace(
            staging: stagingURL,
            final: manifestURL,
            policy: .removeFinalThenMove
        )
    }

    /// Atomically write `samples` (in `format`) under `key`. Stages to a
    /// sibling `.staging-<uuid>` file, then renames into place. Returns
    /// the final URL.
    @discardableResult
    public func store(
        samples: [Float],
        format: AudioFormat,
        key: CacheKey
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )

        let finalURL = cacheURL(for: key)
        let stagingURL = SuperscribeFS.stagingURL(beside: finalURL, label: "\(key.digest).wav")

        let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(format.channels),
            interleaved: false
        )!

        // WAV settings matching the in-memory float32 samples bit-for-bit.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(format.sampleRate),
            AVNumberOfChannelsKey: format.channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let outputFile: AVAudioFile
        do {
            if SuperscribeKitTestHooks.forceCacheStoreOpenFailure == true {
                throw CocoaError(.fileWriteNoPermission)
            }
            outputFile = try AVAudioFile(
                forWriting: stagingURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        }
        catch {
            throw AudioPreparerError.conversionFailed(
                "Cannot open cache file for writing: \(error.localizedDescription)"
            )
        }

        // Write in chunks to keep peak memory bounded.
        let chunkFrames = 65_536
        let totalFrames = samples.count
        var offset = 0
        do {
            while offset < totalFrames {
                let count = min(chunkFrames, totalFrames - offset)
                let buffer: AVAudioPCMBuffer? =
                    if SuperscribeKitTestHooks.forceCacheStoreWriteBufferFailure == true {
                        nil
                    }
                    else {
                        AVAudioPCMBuffer(
                            pcmFormat: avFormat,
                            frameCapacity: AVAudioFrameCount(count)
                        )
                    }
                guard let buffer else {
                    throw AudioPreparerError.conversionFailed(
                        "Cannot allocate cache write buffer"
                    )
                }
                buffer.frameLength = AVAudioFrameCount(count)
                samples.withUnsafeBufferPointer { src in
                    let base = src.baseAddress!.advanced(by: offset)
                    buffer.floatChannelData![0].update(from: base, count: count)
                }
                try outputFile.write(from: buffer)
                if SuperscribeKitTestHooks.forceCacheStoreMidWriteFailure == true {
                    throw CocoaError(.fileWriteUnknown)
                }
                offset += count
            }
        }
        catch {
            if let forced = SuperscribeKitTestHooks.forceCacheStoreWriteError {
                try? FileManager.default.removeItem(at: stagingURL)
                throw forced
            }
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }

        // Closing happens on dealloc; ensure the file is closed before the
        // rename by dropping our reference.
        _ = outputFile

        do {
            if SuperscribeKitTestHooks.forceCacheStoreAtomicReplaceFailure == true {
                throw CocoaError(.fileWriteUnknown)
            }
            try SuperscribeFS.atomicReplace(
                staging: stagingURL,
                final: finalURL,
                policy: .removeFinalThenMove
            )
        }
        catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }

        // Update manifest so `superscribe cache --list` can show source filenames.
        try? updateManifest(
            adding: ManifestEntry(digest: key.digest, sourcePath: key.sourcePath, storedAt: Date())
        )

        return finalURL
    }
}
