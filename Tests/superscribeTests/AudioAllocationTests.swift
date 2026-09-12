import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Audio allocation and validation", .serialized, ResetSharedStateTrait())
struct AudioAllocationTests {
    @Test func allocationAndChannelFailuresAreReported() throws -> Void {
        let format = try AudioBuffers.format(.asr16kMono)
        AudioBuffers.$dependencies.withValue(.init(allocate: { _, _ in nil })) {
            #expect(throws: AudioPreparerError.self) { _ = try AudioBuffers.make(format: format, frames: 1) }
        }
        AudioBuffers.$dependencies.withValue(.init(format: { _ in nil })) {
            #expect(throws: AudioPreparerError.self) { _ = try AudioBuffers.format(.asr16kMono) }
        }
        let integerFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let integerBuffer = try AudioBuffers.make(format: integerFormat, frames: 1)
        #expect(throws: AudioPreparerError.self) { _ = try AudioBuffers.channels(integerBuffer) }
        let stereo = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: false))
        #expect(throws: AudioPreparerError.self) {
            try StreamingAudioConverter.convert(from: format, to: stereo, read: { _ in nil }, emit: { _ in })
        }
    }

    @Test func preparedAudioRejectsWrongFormatAndEmptySlicesAreSafe() throws -> Void {
        let source = try TestHelpers.makeTempSineWAV(name: "wrong-format", sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: source) }
        #expect(throws: AudioPreparerError.self) { _ = try PreparedAudio(url: source, format: .asr16kMono, temporary: false) }
        let audio = try AudioPreparer(targetFormat: .asr16kMono).prepare(url: source)
        #expect(try audio.samples(in: .init(start: 3, end: 4)).isEmpty == true)
        let file = try AVAudioFile(forReading: source)
        var count = 0
        try StreamingAudioConverter.convert(file: file, to: AudioBuffers.format(.asr16kMono)) { count += Int($0.frameLength) }
        #expect(count == 16_000)
        #expect(InputValidationError("test").errorDescription == "test")
    }
}
