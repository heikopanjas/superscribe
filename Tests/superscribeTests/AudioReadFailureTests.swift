import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Premature audio EOF", .serialized, ResetSharedStateTrait())
struct AudioReadFailureTests {
    @Test func zeroFrameReadBeforeDeclaredEndFails() throws -> Void {
        let source = try TestHelpers.makeTempSineWAV(name: "short-read")
        defer { try? FileManager.default.removeItem(at: source) }
        let file = try AVAudioFile(forReading: source)
        let buffer = try AudioBuffers.make(format: file.processingFormat, frames: 100)
        AudioBuffers.$dependencies.withValue(.init(read: { _, buffer, _ in buffer.frameLength = 0 })) {
            #expect(throws: CocoaError.self) { try AudioFileReading.read(file, into: buffer, count: 100) }
        }
    }
}
