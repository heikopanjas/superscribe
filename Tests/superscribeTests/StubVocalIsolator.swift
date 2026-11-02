import Foundation

@testable import SuperscribeKit

struct StubVocalIsolator: VocalIsolator {
    let calls: Counter

    func prepare(source: URL, targetFormat: AudioFormat, cache: ConvertedAudioCache?, onProgress: (@Sendable (ConversionProgress) -> Void)?) async throws -> PreparedAudio {
        await self.calls.increment()
        let audio = try AudioPreparer(targetFormat: targetFormat, cache: cache).prepare(url: source)
        onProgress?(ConversionProgress(source: source, framesProcessed: audio.frameCount, framesTotal: audio.frameCount, fraction: 1))
        return audio
    }
}
