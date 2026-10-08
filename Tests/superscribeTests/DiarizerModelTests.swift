import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Diarizer model", .serialized, ResetSharedStateTrait())
struct DiarizerModelTests {
    @Test func selectsThePresetBundleAndSilenceEmbedding() -> Void {
        let siblings = [
            "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/coremldata.bin", "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/weights/weight.bin",
            "monolithic/v2/Nemotron3Diarizer_fast32.mlmodelc/coremldata.bin", "split/Nemotron3Diarizer_s32_split_w8a8.mlmodelc/coremldata.bin",
            "learnable_sil_emb.bin", "pre_encode_proj_t.bin", "README.md"
        ].map { HuggingFaceHub.HFSibling(rfilename: $0, size: 3) }
        let files = DiarizerModel.files(in: siblings)
        #expect(files.map(\.relativePath) == ["Nemotron3Diarizer_fast128.mlmodelc/coremldata.bin", "Nemotron3Diarizer_fast128.mlmodelc/weights/weight.bin", "learnable_sil_emb.bin"])
        #expect(files.map(\.rfilename).first == "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/coremldata.bin")
        #expect(files.allSatisfy { $0.expectedSize == 3 } == true)
    }

    @Test func installsUnderTheDiarizerModelsDirectory() throws -> Void {
        let path = try DiarizerModel.installPath()
        #expect(path.deletingLastPathComponent().standardizedFileURL.path == SuperscribePaths.diarizerModelsDirectory().standardizedFileURL.path)
        #expect(path.lastPathComponent == "nemotron-3-diarization-fast128")
    }

    @Test func completeInstallationIsRecognized() throws -> Void {
        try TestHelpers.withTempDirectory(prefix: "diarizer-complete") { root in
            try TestHelpers.makeDiarizerInstallation(at: root)
            #expect(DiarizerModel.isInstalled(at: root) == true)
        }
    }

    @Test func missingArtifactsOrStaleWeightsAreNotInstalled() throws -> Void {
        try TestHelpers.withTempDirectory(prefix: "diarizer-incomplete") { root in
            #expect(DiarizerModel.isInstalled(at: root) == false)
            try TestHelpers.makeDiarizerInstallation(at: root)
            try Data("older".utf8).write(to: root.appendingPathComponent(DiarizerModel.weightsMarker))
            #expect(DiarizerModel.isInstalled(at: root) == false)
            try FileManager.default.removeItem(at: root.appendingPathComponent(DiarizerModel.weightsMarker))
            #expect(DiarizerModel.isInstalled(at: root) == false)
            try DiarizerModel.writeMarker(in: root)
            try FileManager.default.removeItem(at: root.appendingPathComponent("learnable_sil_emb.bin"))
            #expect(DiarizerModel.isInstalled(at: root) == false)
        }
    }
}
