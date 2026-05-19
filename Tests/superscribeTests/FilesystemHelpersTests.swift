import Foundation
import Testing

@testable import SuperscribeKit

@Suite("SuperscribeFS", .serialized, ResetSharedStateTrait())
struct FilesystemHelpersTests {
    @Test func stagingURLUsesBasenameAndUUID() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("model.bin")
        let staging = SuperscribeFS.stagingURL(beside: base)
        #expect(staging.deletingLastPathComponent() == base.deletingLastPathComponent())
        #expect(staging.lastPathComponent.hasPrefix("model.bin.staging-"))
    }

    @Test func isExistingFileAndDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: file)

        #expect(SuperscribeFS.isExistingDirectory(at: dir) == true)
        #expect(SuperscribeFS.isExistingFile(at: file) == true)
        #expect(SuperscribeFS.isExistingFile(at: dir) == false)
    }

    @Test func containsCompiledCoreMLBundle() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ml-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(SuperscribeFS.containsCompiledCoreMLBundle(at: dir) == false)
        let bundle = dir.appendingPathComponent("model.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        #expect(SuperscribeFS.containsCompiledCoreMLBundle(at: dir) == true)
    }

    @Test func atomicReplaceRemoveFinalThenMove() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("atomic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let final = parent.appendingPathComponent("target.txt")
        try Data("old".utf8).write(to: final)
        let staging = parent.appendingPathComponent("target.txt.staging-test")
        try Data("new".utf8).write(to: staging)

        try SuperscribeFS.atomicReplace(
            staging: staging,
            final: final,
            policy: .removeFinalThenMove
        )
        #expect(String(data: try Data(contentsOf: final), encoding: .utf8) == "new")
    }

    @Test func atomicReplaceDiscardsStagingWhenFinalExists() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("atomic2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let final = parent.appendingPathComponent("keep.txt")
        try Data("kept".utf8).write(to: final)
        let staging = parent.appendingPathComponent("keep.txt.staging-test")
        try Data("discard".utf8).write(to: staging)

        try SuperscribeFS.atomicReplace(
            staging: staging,
            final: final,
            policy: .discardStagingIfFinalExists
        )
        #expect(String(data: try Data(contentsOf: final), encoding: .utf8) == "kept")
        #expect(FileManager.default.fileExists(atPath: staging.path) == false)
    }
}
