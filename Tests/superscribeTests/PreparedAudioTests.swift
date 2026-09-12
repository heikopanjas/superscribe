import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("File-backed audio", .serialized, ResetSharedStateTrait())
struct PreparedAudioTests {
    @Test func temporaryOwnershipAndPersistentReuse() throws -> Void {
        let source = try TestHelpers.makeTempSineWAV(name: "prepared", durationSeconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let temporary: URL = try {
            let audio = try AudioPreparer(targetFormat: .asr16kMono).prepare(url: source)
            #expect(audio.frameCount == 32_000)
            #expect(try audio.samples(in: .init(start: 1, end: 1.1)).count == 1600)
            #expect(try String(decoding: Data(contentsOf: audio.url).prefix(4), as: UTF8.self) == "RIFF")
            return audio.url
        }()
        #expect(FileManager.default.fileExists(atPath: temporary.path) == false)
        try TestHelpers.withTempDirectory { root in
            let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: ConvertedAudioCache(root: root))
            let first = try preparer.prepare(url: source)
            let second = try preparer.prepare(url: source)
            #expect(first.url == second.url)
            #expect(try first.samples(in: .init(start: 0, end: 2)) == second.samples(in: .init(start: 0, end: 2)))
        }
    }

    @Test(arguments: [8_000.0, 22_050, 44_100, 48_000])
    func finiteBufferConversionDrainsTail(rate: Double) throws -> Void {
        let sourceFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false))
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(rate * 2)))
        source.frameLength = source.frameCapacity
        let channel = try #require(source.floatChannelData?[0])
        channel.initialize(repeating: 0.5, count: Int(source.frameLength))
        var output: [Float] = []
        try StreamingAudioConverter.convert(buffer: source, to: target) { buffer in
            #expect(buffer.frameLength <= StreamingAudioConverter.chunkFrames)
            let samples = try #require(buffer.floatChannelData?[0])
            output.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        }
        #expect(abs(output.count - 32_000) <= 1)
        #expect(abs(try #require(output.dropLast(100).last) - 0.5) < 0.01)
    }

    @Test func cancellationRemovesStagingBeforePublication() throws -> Void {
        let source = try TestHelpers.makeTempSineWAV(name: "cancel-preparation", durationSeconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        try TestHelpers.withTempDirectory { root in
            var checks = 0
            #expect(throws: CancellationError.self) {
                _ = try AudioPreparer(targetFormat: .asr16kMono, cache: ConvertedAudioCache(root: root)).prepare(
                    url: source,
                    checkCancellation: {
                        checks += 1
                        if checks >= 3 { throw CancellationError() }
                    })
            }
            let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(contents.isEmpty == true)
        }
    }
}
