import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Atomic promotion", .serialized, ResetSharedStateTrait())
struct AtomicPromotionTests {
    @Test(arguments: [AtomicReplacePolicy.replaceExisting, .discardStagingIfFinalExists])
    func missingSourcePreservesDestination(policy: AtomicReplacePolicy) throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let final = root.appendingPathComponent("final")
            try Data("original".utf8).write(to: final)
            #expect(throws: (any Error).self) {
                try SuperscribeFS.atomicReplace(staging: root.appendingPathComponent("absent"), final: final, policy: policy)
            }
            #expect(try Data(contentsOf: final) == Data("original".utf8))
        }
    }

    @Test func replacementPromotesWhenDestinationIsAbsent() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let staging = root.appendingPathComponent("staging")
            let final = root.appendingPathComponent("final")
            try Data("new".utf8).write(to: staging)
            try SuperscribeFS.atomicReplace(staging: staging, final: final, policy: .replaceExisting)
            #expect(try Data(contentsOf: final) == Data("new".utf8))
        }
    }

    @Test func nonemptyDirectoryReplacementIsAtomic() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let staging = root.appendingPathComponent("staging")
            let final = root.appendingPathComponent("final")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: final, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: final.appendingPathComponent("old"))
            try Data("new".utf8).write(to: staging.appendingPathComponent("new"))
            try SuperscribeFS.atomicReplace(staging: staging, final: final, policy: .replaceExisting)
            #expect(try Data(contentsOf: final.appendingPathComponent("new")) == Data("new".utf8))
            #expect(FileManager.default.fileExists(atPath: staging.path) == false)
        }
    }
}
