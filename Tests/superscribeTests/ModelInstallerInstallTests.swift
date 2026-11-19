import Foundation
import Testing

@testable import SuperscribeKit

/// End-to-end installer exercises with mocked HuggingFace responses.
@Suite("ModelInstaller network installs", .serialized, ResetSharedStateTrait())
struct ModelInstallerInstallTests {

    @Test func parakeetFolderInstallViaMockDownload() async throws -> Void {
        let tag = "v3"
        let repoId = try ParakeetBackend.huggingFaceRepoId(for: tag)
        let finalDir = try ParakeetBackend.installPath(for: tag)
        try FileManager.default.createDirectory(at: finalDir.appendingPathComponent("Encoder.mlmodelc"), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: finalDir)
        }

        let extras = ["Encoder_v2.mlmodelc/model.mil", "mlpackages/Encoder.mlpackage/Manifest.json", "config.json"]
        let siblings = (TestHelpers.parakeetFiles + extras).map { ["rfilename": $0, "size": 3] as [String: Any] }
        let repoPayload = try JSONSerialization.data(withJSONObject: ["id": repoId, "siblings": siblings])

        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if extras.contains(where: { s.hasSuffix($0) }) == true {
                    Issue.record("Unneeded repository file requested: \(s)")
                }
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, repoPayload)
                }
                if s.contains("/resolve/main/") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data("bin".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    totalSizeBytes: 15,
                    fileCount: 5,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                let url = try await ModelInstaller.install(
                    model: model,
                    backend: .parakeet,
                    session: session,
                    onProgress: { _ in }
                )
                #expect(url.path == finalDir.path)
                #expect(await ModelInstaller.isInstalled(at: finalDir, backend: .parakeet) == true)
                #expect(extras.allSatisfy { FileManager.default.fileExists(atPath: finalDir.appendingPathComponent($0).path) == false } == true)
            }
        )
    }

    @Test(arguments: [Data(), Data([0])])
    func whisperBinInstallRepairsTruncatedDownload(contents: Data) async throws -> Void {
        let fixture = try WhisperDownloadFixture(binary: .init(Data("ggmlstub".utf8)))
        try FileManager.default.createDirectory(at: fixture.binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fixture.binaryURL)
        try await fixture.withSession { session in
            _ = try await ModelInstaller.install(model: fixture.model, backend: .whisperCpp, session: session, onProgress: { _ in })
            #expect(await ModelInstaller.isInstalled(at: fixture.binaryURL, backend: .whisperCpp) == true)
            #expect(WhisperBackend.isEncoderInstalled(modelId: fixture.model.id) == false)
        }
    }

    @Test(arguments: [false, true])
    func whisperBinFastPathInstallsEncoderZip(incompleteEncoder: Bool) async throws -> Void {
        // A binary download would fail: repair must reuse the existing GGML file.
        let binary = Data("existing".utf8)
        let fixture = try WhisperDownloadFixture(binary: .init(binary, status: 500), encoder: WhisperDownloadFixture.validEncoder)
        try FileManager.default.createDirectory(at: fixture.binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try binary.write(to: fixture.binaryURL)
        if incompleteEncoder == true {
            try FileManager.default.createDirectory(at: fixture.encoderURL, withIntermediateDirectories: true)
            try Data().write(to: fixture.encoderURL.appendingPathComponent("model.mil"))
        }
        try await fixture.withSession { session in
            _ = try await ModelInstaller.install(model: fixture.model, backend: .whisperCpp, session: session, onProgress: { _ in })
            #expect(WhisperBackend.isEncoderInstalled(modelId: fixture.model.id) == true)
            #expect(try Data(contentsOf: fixture.binaryURL) == binary)
            #expect(try Data(contentsOf: fixture.encoderURL.appendingPathComponent("model.mil")) == Data("fixture".utf8))
        }
    }

    @Test func concurrentInstallsSerializeForSameDestination() async throws -> Void {
        let fixture = try WhisperDownloadFixture(binary: .init(Data("ZZZZ".utf8)))
        try await fixture.withSession { session in
            async let first = ModelInstaller.install(model: fixture.model, backend: .whisperCpp, session: session, onProgress: { _ in })
            async let second = ModelInstaller.install(model: fixture.model, backend: .whisperCpp, session: session, onProgress: { _ in })
            _ = try await (first, second)
            #expect(await ModelInstaller.isInstalled(at: fixture.binaryURL, backend: .whisperCpp) == true)
        }
    }

    @Test func installFailedWhenEncoderZipUnzipFails() async throws -> Void {
        let binary = Data("existing".utf8)
        let fixture = try WhisperDownloadFixture(binary: .init(binary), encoder: .init(Data("not-a-real-zip".utf8)))
        try FileManager.default.createDirectory(at: fixture.binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try binary.write(to: fixture.binaryURL)
        try await fixture.withSession { session in
            await #expect(throws: ModelInstallationError.self) {
                _ = try await ModelInstaller.install(model: fixture.model, backend: .whisperCpp, session: session, onProgress: { _ in })
            }
            let preserved = try Data(contentsOf: fixture.binaryURL)
            #expect(preserved == binary)
        }
    }

    @Test func removeInstalledParakeetDeletesDirectory() async throws -> Void {
        let tag = "v3"
        let dir = try ParakeetBackend.installPath(for: tag)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("X.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: dir)
        }

        try await ModelInstaller.removeInstalled(modelId: tag, backend: .parakeet)
        #expect(FileManager.default.fileExists(atPath: dir.path) == false)
    }

    @Test func removalPathsParakeetReturnsEmptyWhenAbsent() async throws -> Void {
        let tag = "v3"
        let paths = try await ModelInstaller.removalPaths(modelId: tag, backend: .parakeet)
        #expect(paths.isEmpty == true)
    }
}
