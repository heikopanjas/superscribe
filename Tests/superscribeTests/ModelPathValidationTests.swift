import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Model path confinement", .serialized, ResetSharedStateTrait())
struct ModelPathValidationTests {
    @Test(arguments: ["", "../tiny", "/tiny", ".", "..", "tiny\n", "a\\b"])
    func unsafeIdentifiersCannotBeRemoved(id: String) async -> Void {
        await #expect(throws: (any Error).self) { try await ModelInstaller.removeInstalled(modelId: id, backend: .whisperCpp) }
    }

    @Test(arguments: ["", "/absolute", "../escape", "a/../escape", "a//b", "a/./b", "a\\b", "a\0b"])
    func relativePathsRejectInvalidComponents(path: String) -> Void {
        #expect(throws: (any Error).self) { _ = try ModelPathValidation.components(path) }
    }

    @Test func symlinksCannotEscapeOrResolveToRoot() throws -> Void {
        try TestHelpers.withTempDirectory { parent in
            let root = parent.appendingPathComponent("root")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: parent)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("self"), withDestinationURL: root)
            #expect(throws: (any Error).self) { _ = try ModelPathValidation.resolve("escape/file", under: root) }
            #expect(throws: (any Error).self) { _ = try ModelPathValidation.resolve("self", under: root) }
            #expect(try ModelPathValidation.resolve("weights/a.bin", under: root).path == root.appendingPathComponent("weights/a.bin").path)
        }
    }

    @Test func downloadURLsEncodeReservedCharacters() throws -> Void {
        let url = try ModelPathValidation.downloadURL(repoId: "owner/repo", filename: "weights/a #?%.bin")
        #expect(url.query == nil)
        #expect(url.fragment == nil)
        #expect(url.path.hasSuffix("weights/a #?%.bin") == true)
        #expect(throws: URLError.self) { _ = try HTTPURL.make(host: "[", path: "/") }
    }
}
