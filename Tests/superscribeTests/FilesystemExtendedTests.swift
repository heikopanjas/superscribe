import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("SuperscribeFS extended", .serialized, ResetSharedStateTrait())
struct FilesystemExtendedTests {
    @Test func discardStagingPromotesWhenFinalAbsent() throws -> Void {
        let parent = try TestHelpers.makeTempDir(prefix: "atomic-promote")
        defer { try? FileManager.default.removeItem(at: parent) }
        let final = parent.appendingPathComponent("out.txt")
        let staging = parent.appendingPathComponent("out.txt.staging-test")
        try Data("new".utf8).write(to: staging)
        try SuperscribeFS.atomicReplace(staging: staging, final: final, policy: .discardStagingIfFinalExists)
        #expect(String(data: try Data(contentsOf: final), encoding: .utf8) == "new")
    }
}
