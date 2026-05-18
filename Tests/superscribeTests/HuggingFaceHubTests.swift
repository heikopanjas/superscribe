import Foundation
import Testing

@testable import SuperscribeKit

@Suite("HuggingFaceHub")
struct HuggingFaceHubTests {

    // MARK: - HFRepoInfo / HFSibling

    @Test func decodesRepoInfoWithUnknownFieldsAndMissingSizes() throws {
        let json = """
            {
              "id": "argmaxinc/whisperkit-coreml",
              "lastModified": "2025-09-15T08:30:00.000Z",
              "tags": ["whisper", "coreml"],
              "downloads": 1234,
              "siblings": [
                { "rfilename": "openai_whisper-tiny/MelSpectrogram.mlmodelc/coremldata.bin", "size": 1024 },
                { "rfilename": "openai_whisper-tiny/AudioEncoder.mlmodelc/coremldata.bin" },
                { "rfilename": "README.md", "size": 200 }
              ]
            }
            """.data(using: .utf8)!

        let info = try HuggingFaceHub.decoder()
            .decode(HuggingFaceHub.HFRepoInfo.self, from: json)

        #expect(info.id == "argmaxinc/whisperkit-coreml")
        #expect(info.lastModified != nil)
        #expect(info.siblings.count == 3)
        #expect(info.siblings[1].size == nil)
    }

    // MARK: - HFRepo (author listing)

    @Test func decodesAuthorListing() throws {
        let json = """
            [
              {
                "id": "FluidInference/parakeet-tdt-0.6b-v3-coreml",
                "lastModified": "2025-08-01T00:00:00.000Z",
                "tags": ["asr"]
              },
              {
                "id": "FluidInference/parakeet-tdt-0.6b-v2-coreml"
              }
            ]
            """.data(using: .utf8)!

        let repos = try HuggingFaceHub.decoder()
            .decode([HuggingFaceHub.HFRepo].self, from: json)

        #expect(repos.count == 2)
        #expect(repos[0].id == "FluidInference/parakeet-tdt-0.6b-v3-coreml")
        #expect(repos[0].lastModified != nil)
        #expect(repos[1].lastModified == nil)
    }
}
