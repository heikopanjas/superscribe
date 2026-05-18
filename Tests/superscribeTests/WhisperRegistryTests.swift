import Foundation
import Testing

@testable import SuperscribeKit

@Suite("WhisperBackend.groupSiblings")
struct WhisperRegistryTests {

    @Test func groupsSiblingsByOpenAIWhisperFolder() {
        let siblings: [HuggingFaceHub.HFSibling] = [
            .init(rfilename: "openai_whisper-tiny/MelSpectrogram.mlmodelc/coremldata.bin", size: 100),
            .init(rfilename: "openai_whisper-tiny/AudioEncoder.mlmodelc/coremldata.bin", size: 200),
            .init(rfilename: "openai_whisper-large-v3_turbo/AudioEncoder.mlmodelc/coremldata.bin", size: 5_000_000),
            .init(rfilename: "openai_whisper-large-v3_turbo/TextDecoder.mlmodelc/coremldata.bin", size: 3_000_000),
            // Top-level files are ignored.
            .init(rfilename: "README.md", size: 42),
            // Unknown folder pattern is ignored.
            .init(rfilename: "other_folder/file.bin", size: 99)
        ]

        let result = WhisperBackend.groupSiblings(siblings)
        let byId = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })

        #expect(result.count == 2)

        let tiny = try! #require(byId["tiny"])
        #expect(tiny.totalSizeBytes == 300)
        #expect(tiny.fileCount == 2)
        #expect(tiny.repoId == WhisperBackend.coreMLRepoId)
        #expect(tiny.subpath == "openai_whisper-tiny")

        let turbo = try! #require(byId["large-v3_turbo"])
        #expect(turbo.totalSizeBytes == 8_000_000)
        #expect(turbo.fileCount == 2)
    }

    @Test func returnsEmptyWhenNoMatchingFolders() {
        #expect(WhisperBackend.groupSiblings([]).isEmpty)
        #expect(
            WhisperBackend.groupSiblings([
                .init(rfilename: "config.json", size: 100)
            ]).isEmpty
        )
    }

    @Test func handlesMissingSizes() {
        let siblings: [HuggingFaceHub.HFSibling] = [
            .init(rfilename: "openai_whisper-tiny/file1.bin", size: nil),
            .init(rfilename: "openai_whisper-tiny/file2.bin", size: nil)
        ]
        let result = WhisperBackend.groupSiblings(siblings)
        #expect(result.count == 1)
        // sizeSum stayed 0, so totalSizeBytes ends up nil.
        #expect(result[0].totalSizeBytes == nil)
        #expect(result[0].fileCount == 2)
    }
}
