import AVFoundation
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Metal resource lookup", .serialized, ResetSharedStateTrait())
struct MetalLibraryLocationTests {
    @Test(arguments: [
        "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", "mlx-swift_Cmlx.bundle/default.metallib",
        "mlx.metallib", "Resources/mlx.metallib"
    ])
    func findsPackagedLibraryWithoutDependingOnTheWorkingDirectory(suffix: String) throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let library = root.appendingPathComponent(suffix)
            try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: library)
            let executable = root.appendingPathComponent("superscribe")
            #expect(try MetalLibraryLocation.resolve(executable: executable, bundles: []).resolvingSymlinksInPath() == library.resolvingSymlinksInPath())
            #expect(try MetalLibraryLocation.resolve(executable: nil, bundles: [root]).resolvingSymlinksInPath() == library.resolvingSymlinksInPath())
        }
    }

    @Test func missingEmptyAndDirectoryResourcesProduceAnActionableError() throws -> Void {
        #expect(throws: InputValidationError.self) { try MetalLibraryLocation.resolve(executable: nil, bundles: []) }
        try TestHelpers.withTempDirectory { root in
            let empty = root.appendingPathComponent("mlx-swift_Cmlx.bundle/default.metallib")
            try FileManager.default.createDirectory(at: empty.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: empty)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("mlx.metallib"), withIntermediateDirectories: true)
            do {
                _ = try MetalLibraryLocation.resolve(executable: root.appendingPathComponent("superscribe"), bundles: [])
                Issue.record("Missing shaders must fail before MLX initializes")
            }
            catch {
                #expect(error.localizedDescription.contains("Install mlx-swift_Cmlx.bundle beside superscribe") == true)
            }
        }
    }

    @Test func followsExecutableSymlinksAndKeepsDiskPCMInterleaved() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let executable = root.appendingPathComponent("release/superscribe")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: executable)
            let library = executable.deletingLastPathComponent().appendingPathComponent("mlx.metallib")
            try Data([1]).write(to: library)
            let link = root.appendingPathComponent("superscribe")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
            #expect(try MetalLibraryLocation.resolve(executable: link, bundles: []).resolvingSymlinksInPath() == library.resolvingSymlinksInPath())
        }
        let format = try AudioBuffers.format(.asr16kMono)
        let settings = AudioBuffers.fileSettings(for: format)
        #expect(settings[AVLinearPCMIsNonInterleaved] as? Bool == false)
        #expect(settings[AVSampleRateKey] as? Double == 16_000)
        #expect(format.isInterleaved == false)
    }

    @Test func baseRelativeBundleURLsBecomeAbsoluteLibraryPaths() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let relative = URL(fileURLWithPath: "Contents/Resources", isDirectory: true, relativeTo: root)
            try FileManager.default.createDirectory(at: relative, withIntermediateDirectories: true)
            let library = relative.appendingPathComponent("mlx.metallib")
            try Data([1]).write(to: library)
            let resolved = try MetalLibraryLocation.resolve(executable: nil, bundles: [relative])
            #expect(resolved.baseURL == nil)
            #expect(resolved.path(percentEncoded: false).hasPrefix("/") == true)
            #expect(resolved.path == library.path)
        }
    }

    @Test(.enabled(if: NSUserName() != "root", "Permission checks require an unprivileged user"))
    func unreadableLibrariesAreRejected() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let library = root.appendingPathComponent("mlx.metallib")
            try Data([1]).write(to: library)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: library.path)
            #expect(throws: InputValidationError.self) { try MetalLibraryLocation.resolve(executable: nil, bundles: [root]) }
        }
    }

    @Test func unrelatedFrameworkDefaultLibrariesAreNotSelected() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            try Data([1]).write(to: root.appendingPathComponent("default.metallib"))
            #expect(throws: InputValidationError.self) { try MetalLibraryLocation.resolve(executable: nil, bundles: [root]) }
        }
    }
}
