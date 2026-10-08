import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Model download file selection", .serialized, ResetSharedStateTrait())
struct ModelDownloadFileTests {
    private static func siblings(_ paths: [String], size: Int64? = 2) -> [HuggingFaceHub.HFSibling] {
        return paths.map { HuggingFaceHub.HFSibling(rfilename: $0, size: size) }
    }

    @Test func selectsRootFilesAndPrefixedBundleContents() -> Void {
        let siblings = Self.siblings([
            "vocab.json", "pre/Model.mlmodelc/", "pre/Model.mlmodelc/coremldata.bin", "pre/Model.mlmodelc/weights/weight.bin", "pre/Other.mlmodelc/coremldata.bin",
            "Model.mlmodelc/coremldata.bin", "pre/vocab.json", "README.md"
        ])
        let files = ModelDownloadFile.select(from: siblings, bundles: ["Model.mlmodelc"], files: ["vocab.json"], under: "pre/")
        #expect(files.map(\.rfilename) == ["vocab.json", "pre/Model.mlmodelc/coremldata.bin", "pre/Model.mlmodelc/weights/weight.bin"])
        #expect(files.map(\.relativePath) == ["vocab.json", "Model.mlmodelc/coremldata.bin", "Model.mlmodelc/weights/weight.bin"])
    }

    @Test func totalSizeRequiresEveryKnownSize() -> Void {
        let known = ModelDownloadFile.select(from: Self.siblings(["a", "b"]), bundles: [], files: ["a", "b"])
        let unknown = ModelDownloadFile.select(from: Self.siblings(["a"], size: nil), bundles: [], files: ["a"])
        #expect(ModelDownloadFile.totalSize(of: known) == 4)
        #expect(ModelDownloadFile.totalSize(of: unknown) == nil)
        #expect(ModelDownloadFile.totalSize(of: []) == nil)
    }

    @Test(arguments: ParakeetBackend.knownDescriptors)
    func parakeetSelectionKeepsOnlyLoadedBundlesAndVocabulary(descriptor: ParakeetBackend.ModelDescriptor) -> Void {
        let required = descriptor.bundles.map { "\($0)/coremldata.bin" } + [descriptor.vocabulary]
        let extras = ["Encoder_v2.mlmodelc/coremldata.bin", "mlpackages/Encoder.mlpackage/Manifest.json", "config.json", "parakeet_v3_vocab.json", ".gitattributes"]
        let files = descriptor.files(in: Self.siblings(required + extras))
        #expect(Set(files.map(\.relativePath)) == Set(required))
    }
}
