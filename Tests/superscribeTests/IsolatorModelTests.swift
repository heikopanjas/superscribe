import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Isolation models", .serialized, ResetSharedStateTrait())
struct IsolatorModelTests {
    @Test func flagsSelectTheRequestedModel() throws -> Void {
        #expect(try TranscribeOptions.parse([]).isolationModel == nil)
        #expect(try TranscribeOptions.parse(["--isolate"]).isolationModel == .htdemucs)
        #expect(try TranscribeOptions.parse(["--isolate", "--fine-tune"]).isolationModel == .htdemucsFT)
        #expect(throws: (any Error).self) { try TranscribeOptions.parse(["--fine-tune"]) }
        #expect(throws: (any Error).self) { try TranscribeCommand.parse(["--create-input", ".", "--isolate"]) }
    }

    @Test func installationRequiresExplicitRepairAfterFirstUse() async throws -> Void {
        let count = Counter()
        let operations = IsolatorModelOperations(
            validate: { _, path in _ = try Data(contentsOf: path.appendingPathComponent("weights")) },
            download: { model, path, progress in
                await count.increment()
                progress(
                    DownloadProgress(
                        modelId: model.rawValue, backend: nil, currentFile: "weights", filesCompleted: 0, filesTotal: 1, bytesCompleted: 1, bytesTotal: 1, bytesPerSecond: nil))
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                try Data([1]).write(to: path.appendingPathComponent("weights"))
            })
        try await ModelInstaller.$isolatorOperations.withValue(operations) {
            let model = IsolatorModel.htdemucs
            let path = try await ModelInstaller.installIsolator(model: model)
            #expect(path.path == (try model.installPath()).path)
            #expect(try await ModelInstaller.installIsolator(model: model).path == path.path)
            #expect(await count.value == 1)
            #expect(await ModelInstaller.isIsolatorInstalled(model) == true)
            #expect(try await ModelInstaller.removeIsolator(model: model) == true)
            #expect(try await ModelInstaller.removeIsolator(model: model) == false)
            #expect(await ModelInstaller.isIsolatorInstalled(model) == false)
            await #expect(throws: (any Error).self) { try await ModelInstaller.installIsolator(model: model) }
            #expect(await count.value == 1)
            _ = try await ModelInstaller.installIsolator(model: model, allowRepair: true)
            #expect(await count.value == 2)
            try Data().write(to: path.appendingPathComponent("weights"))
            try FileManager.default.removeItem(at: path.appendingPathComponent("weights"))
            await #expect(throws: (any Error).self) { try await ModelInstaller.installIsolator(model: model) }
            _ = try await ModelInstaller.installIsolator(model: model, allowRepair: true)
            #expect(await count.value == 3)
        }
        #expect(IsolatorModel.allCases.map(\.rawValue) == ["htdemucs", "htdemucs_ft"])
        #expect(IsolatorModel.htdemucs.separationOptions.stem == nil)
        #expect(IsolatorModel.htdemucsFT.separationOptions.stem == "vocals")
        #expect(IsolatorModel.allCases.allSatisfy { $0.separationOptions.seed == 0 && $0.separationOptions.cacheValidation == .verifiedIdentity } == true)
    }

    @Test func failuresRemainRetryableAndInvalidPathsAreRejected() async throws -> Void {
        let operations = IsolatorModelOperations(
            validate: { _, _ in throw CocoaError(.fileReadCorruptFile) },
            download: { _, _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        await ModelInstaller.$isolatorOperations.withValue(operations) {
            await #expect(throws: CocoaError.self) { try await ModelInstaller.installIsolator(model: .htdemucsFT) }
            #expect(FileManager.default.fileExists(atPath: IsolatorModel.htdemucsFT.receiptURL.path) == false)
            #expect(await ModelInstaller.isIsolatorInstalled(.htdemucsFT) == false)
        }
        try await TestHelpers.withTempDirectory { outside in
            let root = SuperscribePaths.isolatorModelsDirectory()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("htdemucs"), withDestinationURL: outside)
            #expect(await ModelInstaller.isIsolatorInstalled(.htdemucs) == false)
        }
        for flags in [["--backend", "parakeet"], ["--diarizer"], ["--remote"], ["--refresh"], ["--json"], ["--set-default", "htdemucs"]] {
            #expect(throws: (any Error).self) { try ModelCommand.parse(["--isolator"] + flags) }
        }
        var command = try ModelCommand.parse(["--isolator", "--rm", "unknown", "--yes"])
        await #expect(throws: (any Error).self) { try await command.run() }
    }
}
