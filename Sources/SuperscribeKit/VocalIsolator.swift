import Foundation

/// Prepares isolated vocals as file-backed audio suitable for the selected ASR backend.
public protocol VocalIsolator: Sendable {
    func prepare(
        source: URL, targetFormat: AudioFormat, cache: ConvertedAudioCache?,
        onProgress: (@Sendable (ConversionProgress) -> Void)?
    ) async throws -> PreparedAudio
}
