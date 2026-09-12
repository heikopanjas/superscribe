import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Artifact integrity", .serialized, ResetSharedStateTrait())
struct ArtifactValidationTests {
    @Test func incompleteParakeetComponentsAndBinarySizesAreRejected() async throws -> Void {
        let incomplete = try ParakeetBackend.installPath(for: "v3")
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        #expect(try ParakeetBackend.installedModels().isEmpty == true)
        try await TestHelpers.withTempDirectory { root in
            let binary = root.appendingPathComponent("model.bin")
            #expect(ModelArtifacts.nonemptyFile(at: binary) == false)
            try Data().write(to: binary)
            #expect(ModelArtifacts.nonemptyFile(at: binary) == false)
            try Data([1, 2, 3]).write(to: binary)
            #expect(await ModelInstaller.isInstalled(at: binary, backend: .whisperCpp, expectedSize: 4) == false)
            #expect(await ModelInstaller.isInstalled(at: binary, backend: .whisperCpp, expectedSize: 3) == true)
            #expect(await ModelInstaller.isInstalled(at: root, backend: .parakeet) == false)
            #expect(await ModelInstaller.isInstalled(at: root, backend: .parakeet, modelId: "unknown") == false)
            try TestHelpers.makeParakeetInstallation(at: root)
            let descriptor = try ParakeetBackend.descriptor(for: "v3")
            #expect(ModelArtifacts.parakeet(at: root, descriptor: descriptor) == true)
            let encoder = root.appendingPathComponent("Encoder.mlmodelc")
            try FileManager.default.removeItem(at: encoder)
            #expect(ModelArtifacts.parakeet(at: root, descriptor: descriptor) == false)
            try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
            #expect(ModelArtifacts.parakeet(at: root, descriptor: descriptor) == false)
        }
        #expect(try ParakeetBackend.mapRepos([.init(id: "unrelated/parakeet-tdt-0.6b-v3-coreml", lastModified: nil)]).isEmpty == true)
    }

    @Test(arguments: [false, true])
    func descriptorRejectsForeignRepositoryOrSubdirectory(foreign: Bool) async throws -> Void {
        let repository = try ParakeetBackend.huggingFaceRepoId(for: "v3")
        let model = RemoteModelInfo(id: "v3", repoId: foreign ? "other/repository" : repository, subpath: foreign ? nil : "other", repoURL: URL(fileURLWithPath: "/unused"))
        await #expect(throws: UnsupportedModelError.self) { _ = try await ModelInstaller.install(model: model, backend: .parakeet) }
    }

    @Test(arguments: [Double.nan, .infinity, -1, 0, 0.5, Double(Int.max)])
    func invalidSampleRatesThrow(rate: Double) -> Void {
        #expect(throws: AudioPreparerError.self) { _ = try AudioValidation.sampleRate(rate) }
    }

    @Test func speechErrorsHaveActionableDescriptions() -> Void {
        let errors: [AppleSpeechError] = [
            .runtimeUnavailable, .localeUnsupported("x"), .localeInstallFailed(underlying: TestError.fail), .transcriptionFailed, .audioConversionFailed, .allocationLimitReached
        ]
        #expect(errors.allSatisfy { $0.errorDescription?.isEmpty == false } == true)
    }
}
