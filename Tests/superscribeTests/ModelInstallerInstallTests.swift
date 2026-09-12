import Foundation
import Testing

@testable import SuperscribeKit

/// End-to-end installer exercises with mocked HuggingFace responses.
@Suite("ModelInstaller network installs", .serialized, ResetSharedStateTrait())
struct ModelInstallerInstallTests {

    private func tearDownMocks() -> Void {
        MockURLSessionHelpers.reset()
    }

    @Test func parakeetFolderInstallViaMockDownload() async throws -> Void {
        let tag = "v3"
        let repoId = try ParakeetBackend.huggingFaceRepoId(for: tag)
        let finalDir = try ParakeetBackend.installPath(for: tag)
        try FileManager.default.createDirectory(at: finalDir.appendingPathComponent("Encoder.mlmodelc"), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: finalDir)
        }

        let siblings = TestHelpers.parakeetFiles.map { ["rfilename": $0, "size": 3] as [String: Any] }
        let repoPayload = try JSONSerialization.data(withJSONObject: ["id": repoId, "siblings": siblings])

        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
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
                    subpath: nil,
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
            }
        )
    }

    @Test func whisperBinInstallRepairsTruncatedDownload() async throws -> Void {
        let tag = "wt-\(UUID().uuidString.prefix(8))"
        let repoId = WhisperBackend.huggingFaceRepoId
        let binURL = WhisperBackend.installPath(for: tag)
        try FileManager.default.createDirectory(at: binURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: binURL)
        defer {
            try? FileManager.default.removeItem(at: binURL)
        }

        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-\(tag).bin","size":8}
            ]}
            """

        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(repoPayload.utf8))
                }
                if s.contains("/resolve/main/ggml-\(tag).bin") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data("ggmlstub".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    subpath: nil,
                    totalSizeBytes: 8,
                    fileCount: 1,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                _ = try await ModelInstaller.install(
                    model: model,
                    backend: .whisperCpp,
                    session: session,
                    onProgress: { _ in }
                )
                #expect(await ModelInstaller.isInstalled(at: binURL, backend: .whisperCpp) == true)
                #expect(WhisperBackend.isEncoderInstalled(modelId: tag) == false)
            }
        )
    }

    @Test func whisperBinFastPathInstallsEncoderZip() async throws -> Void {
        defer { self.tearDownMocks() }
        let tag = "wt-enc-\(UUID().uuidString.prefix(8))"
        let repoId = WhisperBackend.huggingFaceRepoId
        let binURL = WhisperBackend.installPath(for: tag)
        let encoderURL = WhisperBackend.encoderInstallPath(for: tag)
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)

        try FileManager.default.createDirectory(
            at: binURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: binURL.path, contents: Data("existing".utf8))
        defer {
            try? FileManager.default.removeItem(at: binURL)
            try? FileManager.default.removeItem(at: encoderURL)
        }

        try await TestHelpers.withTempDirectory(prefix: "encoder-zip-build") { zipBuild in
            let bundleName = "\(WhisperBackend.encoderBaseId(for: tag))-encoder.mlmodelc"
            let zipData = ZIPFixture.encoderBundle(named: bundleName)
            let repoPayload = """
                {"id":"\(repoId)","lastModified":null,"siblings":[
                  {"rfilename":"ggml-\(tag).bin","size":8},
                  {"rfilename":"\(zipName)","size":\(zipData.count)}
                ]}
                """

            try await MockURLSessionHelpers.withMockHandler(
                { req in
                    guard let url = req.url else { throw URLError(.badURL) }
                    let s = url.absoluteString
                    if s.contains("/api/models/\(repoId)") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data(repoPayload.utf8))
                    }
                    let resolveSuffix = "/resolve/main/\(zipName)"
                    if s.contains(resolveSuffix) == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, zipData)
                    }
                    throw URLError(.unsupportedURL)
                },
                { session in
                    let model = RemoteModelInfo(
                        id: tag,
                        repoId: repoId,
                        subpath: nil,
                        totalSizeBytes: 8,
                        fileCount: 2,
                        lastModified: nil,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )

                    _ = try await ModelInstaller.install(
                        model: model,
                        backend: .whisperCpp,
                        session: session,
                        onProgress: { _ in }
                    )
                    #expect(WhisperBackend.isEncoderInstalled(modelId: tag) == true)
                }
            )
        }
    }

    @Test func concurrentInstallsSerializeForSameDestination() async throws -> Void {
        let tag = "wt-ser-\(UUID().uuidString.prefix(8))"
        let repoId = WhisperBackend.huggingFaceRepoId
        let binURL = WhisperBackend.installPath(for: tag)
        defer {
            try? FileManager.default.removeItem(at: binURL)
        }

        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-\(tag).bin","size":4}
            ]}
            """

        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(repoPayload.utf8))
                }
                if s.contains("/resolve/main/ggml-\(tag).bin") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data("ZZZZ".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    subpath: nil,
                    totalSizeBytes: 4,
                    fileCount: 1,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                let session = session
                async let first = try ModelInstaller.install(
                    model: model,
                    backend: .whisperCpp,
                    session: session,
                    onProgress: { _ in }
                )
                async let second = try ModelInstaller.install(
                    model: model,
                    backend: .whisperCpp,
                    session: session,
                    onProgress: { _ in }
                )
                _ = try await (first, second)
                #expect(await ModelInstaller.isInstalled(at: binURL, backend: .whisperCpp) == true)
            }
        )
    }

    @Test func installFailedWhenEncoderZipUnzipFails() async throws -> Void {
        let tag = "wt-badzip-\(UUID().uuidString.prefix(8))"
        let repoId = WhisperBackend.huggingFaceRepoId
        let binURL = WhisperBackend.installPath(for: tag)
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)

        try FileManager.default.createDirectory(
            at: binURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: binURL.path, contents: Data("existing".utf8))
        defer {
            try? FileManager.default.removeItem(at: binURL)
            try? FileManager.default.removeItem(at: WhisperBackend.encoderInstallPath(for: tag))
        }

        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-\(tag).bin","size":8},
              {"rfilename":"\(zipName)","size":12}
            ]}
            """

        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(repoPayload.utf8))
                }
                if s.contains("/resolve/main/\(zipName)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data("not-a-real-zip".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    subpath: nil,
                    totalSizeBytes: 8,
                    fileCount: 2,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                await #expect(throws: ModelInstallationError.self) {
                    _ = try await ModelInstaller.install(
                        model: model,
                        backend: .whisperCpp,
                        session: session,
                        onProgress: { _ in }
                    )
                }
            }
        )
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
