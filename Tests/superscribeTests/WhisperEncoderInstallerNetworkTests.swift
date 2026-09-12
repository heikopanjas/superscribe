import Foundation
import Testing

@testable import SuperscribeKit

@Suite("WhisperEncoderInstaller networking", .serialized, ResetSharedStateTrait())
struct WhisperEncoderInstallerNetworkTests {

    @Test func totalInstallBytesSumsBinAndEncoderZip() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "probe-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-\(tag).bin","size":100},
              {"rfilename":"\(zipName)","size":40}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    subpath: nil,
                    totalSizeBytes: nil,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == 140)
            }
        )
    }

    @Test func totalInstallBytesFallsBackWhenBinSiblingMissing() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"README.md","size":10}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: "missing-bin-case",
                    repoId: repoId,
                    subpath: nil,
                    totalSizeBytes: 999,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == 999)
            }
        )
    }

    @Test func installIfNeededNoZipSiblingReturnsEarly() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "no-zip-\(UUID().uuidString.prefix(6))"
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-\(tag).bin","size":10}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    subpath: nil,
                    totalSizeBytes: 10,
                    fileCount: 1,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                try await WhisperEncoderInstaller.installIfNeeded(
                    model: model,
                    session: session,
                    onProgress: { _ in }
                )
                #expect(WhisperBackend.isEncoderInstalled(modelId: tag) == false)
            }
        )
    }

    @Test func installIfNeededInstallsFromZip() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-ok-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let encoderFinal = WhisperBackend.encoderInstallPath(for: tag)
        defer {
            try? FileManager.default.removeItem(at: encoderFinal)
        }

        try await TestHelpers.withTempDirectory(prefix: "wenc-zip") { build in
            let bundleName = "\(WhisperBackend.encoderBaseId(for: tag))-encoder.mlmodelc"
            let zipData = ZIPFixture.encoderBundle(named: bundleName)

            let payload = """
                {"id":"\(repoId)","lastModified":null,"siblings":[
                  {"rfilename":"\(zipName)","size":\(zipData.count)}
                ]}
                """

            try await MockURLSessionHelpers.withMockHandler(
                { req in
                    guard let url = req.url else { throw URLError(.badURL) }
                    let s = url.absoluteString
                    if s.contains("/api/models/\(repoId)") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
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
                        totalSizeBytes: Int64(zipData.count),
                        fileCount: 1,
                        lastModified: nil,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )

                    try await WhisperEncoderInstaller.installIfNeeded(
                        model: model,
                        session: session,
                        onProgress: { _ in }
                    )
                    #expect(WhisperBackend.isEncoderInstalled(modelId: tag) == true)
                }
            )
        }
    }

    @Test func installIfNeededThrowsWhenMlmodelcMissingInZip() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-bad-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)

        try await TestHelpers.withTempDirectory(prefix: "wenc-bad") { build in
            let bundle = build.appendingPathComponent("wrong-name.mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let zipData = ZIPFixture.encoderBundle(named: "wrong-name.mlmodelc")

            let payload = """
                {"id":"\(repoId)","lastModified":null,"siblings":[
                  {"rfilename":"\(zipName)","size":\(zipData.count)}
                ]}
                """

            try await MockURLSessionHelpers.withMockHandler(
                { req in
                    guard let url = req.url else { throw URLError(.badURL) }
                    let s = url.absoluteString
                    if s.contains("/api/models/\(repoId)") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
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
                        totalSizeBytes: Int64(zipData.count),
                        fileCount: 1,
                        lastModified: nil,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )

                    await #expect(throws: ModelInstallationError.self) {
                        try await WhisperEncoderInstaller.installIfNeeded(
                            model: model,
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            )
        }
    }

    @Test func installIfNeededThrowsWhenEncoderBundleIsFile() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-file-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let encoderName = "\(WhisperBackend.encoderBaseId(for: tag))-encoder.mlmodelc"

        try await TestHelpers.withTempDirectory(prefix: "wenc-file") { build in
            let fakeFile = build.appendingPathComponent(encoderName)
            try Data("not-a-directory".utf8).write(to: fakeFile)
            let zipData = ZIPFixture.archive([.init(name: encoderName, data: Data("file".utf8))])

            let payload = """
                {"id":"\(repoId)","lastModified":null,"siblings":[
                  {"rfilename":"\(zipName)","size":\(zipData.count)}
                ]}
                """

            try await MockURLSessionHelpers.withMockHandler(
                { req in
                    guard let url = req.url else { throw URLError(.badURL) }
                    let s = url.absoluteString
                    if s.contains("/api/models/\(repoId)") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
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
                        totalSizeBytes: Int64(zipData.count),
                        fileCount: 1,
                        lastModified: nil,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )

                    await #expect(throws: ModelInstallationError.self) {
                        try await WhisperEncoderInstaller.installIfNeeded(
                            model: model,
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            )
        }
    }

    @Test func installIfNeededCompletesWhenZipSizeNil() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-nil-size-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let encoderFinal = WhisperBackend.encoderInstallPath(for: tag)
        defer {
            try? FileManager.default.removeItem(at: encoderFinal)
        }

        try await TestHelpers.withTempDirectory(prefix: "wenc-nil-size") { build in
            let bundleName = "\(WhisperBackend.encoderBaseId(for: tag))-encoder.mlmodelc"
            let zipData = ZIPFixture.encoderBundle(named: bundleName)

            let payload = """
                {"id":"\(repoId)","lastModified":null,"siblings":[
                  {"rfilename":"\(zipName)","size":null}
                ]}
                """

            try await MockURLSessionHelpers.withMockHandler(
                { req in
                    guard let url = req.url else { throw URLError(.badURL) }
                    let s = url.absoluteString
                    if s.contains("/api/models/\(repoId)") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
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
                        totalSizeBytes: nil,
                        fileCount: 1,
                        lastModified: nil,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )

                    try await WhisperEncoderInstaller.installIfNeeded(
                        model: model,
                        session: session,
                        onProgress: { _ in }
                    )
                    #expect(WhisperBackend.isEncoderInstalled(modelId: tag) == true)
                }
            )
        }
    }

    @Test func installIfNeededUnzipFailureUsesFallbackMessage() async throws -> Void {
        defer { SuperscribeKitTestHooks.forceUnzipInvalidStderr = false }
        SuperscribeKitTestHooks.forceUnzipInvalidStderr = true

        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-unzip-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"\(zipName)","size":12}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/\(zipName)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data("not-a-zip".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    subpath: nil,
                    totalSizeBytes: 12,
                    fileCount: 1,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                await #expect(throws: ModelInstallationError.self) {
                    try await WhisperEncoderInstaller.installIfNeeded(
                        model: model,
                        session: session,
                        onProgress: { _ in }
                    )
                }
            }
        )
    }

    @Test func decodeUnzipStderrUsesUTF8Payload() -> Void {
        defer { SuperscribeKitTestHooks.forceUnzipInvalidStderr = false }
        SuperscribeKitTestHooks.forceUnzipInvalidStderr = false
        #expect(WhisperEncoderInstaller.decodeUnzipStderr(raw: Data("bad zip".utf8)) == "bad zip")
    }

    @Test func decodeUnzipStderrUsesFallbackForInvalidUTF8() -> Void {
        defer { SuperscribeKitTestHooks.forceUnzipInvalidStderr = false }
        SuperscribeKitTestHooks.forceUnzipInvalidStderr = true
        #expect(WhisperEncoderInstaller.decodeUnzipStderr(raw: Data("ignored".utf8)) == "unzip failed")
    }

    @Test func decodeUnzipStderrFallsBackWhenRawUTF8Invalid() -> Void {
        defer { SuperscribeKitTestHooks.forceUnzipInvalidStderr = false }
        SuperscribeKitTestHooks.forceUnzipInvalidStderr = false
        #expect(WhisperEncoderInstaller.decodeUnzipStderr(raw: Data([0xFF, 0xFE])) == "unzip failed")
    }

    @Test func installIfNeededUnzipFailureReadsRawStderr() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-raw-err-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"\(zipName)","size":12}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/\(zipName)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data("not-a-zip".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    subpath: nil,
                    totalSizeBytes: 12,
                    fileCount: 1,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )

                await #expect(throws: ModelInstallationError.self) {
                    try await WhisperEncoderInstaller.installIfNeeded(
                        model: model,
                        session: session,
                        onProgress: { _ in }
                    )
                }
            }
        )
    }

    @Test func installIfNeededMissingBundleWhenEnumeratorForcedNil() async throws -> Void {
        defer { SuperscribeKitTestHooks.forceEncoderBundleEnumeratorNil = false }
        SuperscribeKitTestHooks.forceEncoderBundleEnumeratorNil = true

        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-nil-enum-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)

        try await TestHelpers.withTempDirectory(prefix: "wenc-nil-enum") { build in
            let bundleName = "\(WhisperBackend.encoderBaseId(for: tag))-encoder.mlmodelc"
            let zipData = ZIPFixture.encoderBundle(named: bundleName)

            let payload = """
                {"id":"\(repoId)","lastModified":null,"siblings":[
                  {"rfilename":"\(zipName)","size":\(zipData.count)}
                ]}
                """

            try await MockURLSessionHelpers.withMockHandler(
                { req in
                    guard let url = req.url else { throw URLError(.badURL) }
                    let s = url.absoluteString
                    if s.contains("/api/models/\(repoId)") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
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
                        totalSizeBytes: Int64(zipData.count),
                        fileCount: 1,
                        lastModified: nil,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )

                    await #expect(throws: ModelInstallationError.self) {
                        try await WhisperEncoderInstaller.installIfNeeded(
                            model: model,
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            )
        }
    }
}
