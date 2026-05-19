import Foundation
import Testing

@testable import SuperscribeKit

@Suite("WhisperEncoderInstaller networking", .serialized, ResetSharedStateTrait())
struct WhisperEncoderInstallerNetworkTests {

    private func writeZip(bundleParent: URL, bundleName: String, zipURL: URL) throws {
        let bundle = bundleParent.appendingPathComponent(bundleName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("inner", isDirectory: true),
            withIntermediateDirectories: true
        )
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-q", "-r", zipURL.path, bundle.lastPathComponent]
        proc.currentDirectoryURL = bundleParent
        try proc.run()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0)
    }

    @Test func totalInstallBytesSumsBinAndEncoderZip() async throws {
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
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                )

                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == 140)
            }
        )
    }

    @Test func totalInstallBytesFallsBackWhenBinSiblingMissing() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"README.md","size":10}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                )

                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == 999)
            }
        )
    }

    @Test func installIfNeededNoZipSiblingReturnsEarly() async throws {
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
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
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

    @Test func installIfNeededInstallsFromZip() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-ok-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let encoderFinal = WhisperBackend.encoderInstallPath(for: tag)
        defer {
            try? FileManager.default.removeItem(at: encoderFinal)
        }

        try await TestHelpers.withTempDirectory(prefix: "wenc-zip") { build in
            let zipURL = build.appendingPathComponent("encoder.zip")
            let bundleName = "\(WhisperBackend.encoderBaseId(for: tag))-encoder.mlmodelc"
            try writeZip(bundleParent: build, bundleName: bundleName, zipURL: zipURL)
            let zipData = try Data(contentsOf: zipURL)

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
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
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

    @Test func installIfNeededThrowsWhenMlmodelcMissingInZip() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-bad-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)

        try await TestHelpers.withTempDirectory(prefix: "wenc-bad") { build in
            let bundle = build.appendingPathComponent("wrong-name.mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let zipURL = build.appendingPathComponent("bad.zip")
            try writeZip(bundleParent: build, bundleName: "wrong-name.mlmodelc", zipURL: zipURL)
            let zipData = try Data(contentsOf: zipURL)

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
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
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

    @Test func installIfNeededCompletesWhenZipSizeNil() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-nil-size-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let encoderFinal = WhisperBackend.encoderInstallPath(for: tag)
        defer {
            try? FileManager.default.removeItem(at: encoderFinal)
        }

        try await TestHelpers.withTempDirectory(prefix: "wenc-nil-size") { build in
            let zipURL = build.appendingPathComponent("encoder.zip")
            let bundleName = "\(WhisperBackend.encoderBaseId(for: tag))-encoder.mlmodelc"
            try writeZip(bundleParent: build, bundleName: bundleName, zipURL: zipURL)
            let zipData = try Data(contentsOf: zipURL)

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
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
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

    @Test func installIfNeededUnzipFailureUsesFallbackMessage() async throws {
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
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/\(zipName)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
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

    @Test func decodeUnzipStderrUsesUTF8Payload() {
        defer { SuperscribeKitTestHooks.forceUnzipInvalidStderr = false }
        SuperscribeKitTestHooks.forceUnzipInvalidStderr = false
        #expect(WhisperEncoderInstaller.decodeUnzipStderr(raw: Data("bad zip".utf8)) == "bad zip")
    }

    @Test func decodeUnzipStderrUsesFallbackForInvalidUTF8() {
        defer { SuperscribeKitTestHooks.forceUnzipInvalidStderr = false }
        SuperscribeKitTestHooks.forceUnzipInvalidStderr = true
        #expect(WhisperEncoderInstaller.decodeUnzipStderr(raw: Data("ignored".utf8)) == "unzip failed")
    }

    @Test func installIfNeededUnzipFailureReadsRawStderr() async throws {
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
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/\(zipName)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
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

    @Test func installIfNeededMissingBundleWhenEnumeratorForcedNil() async throws {
        defer { SuperscribeKitTestHooks.forceEncoderBundleEnumeratorNil = false }
        SuperscribeKitTestHooks.forceEncoderBundleEnumeratorNil = true

        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zip-nil-enum-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)

        try await TestHelpers.withTempDirectory(prefix: "wenc-nil-enum") { build in
            let zipURL = build.appendingPathComponent("encoder.zip")
            let bundleName = "\(WhisperBackend.encoderBaseId(for: tag))-encoder.mlmodelc"
            try writeZip(bundleParent: build, bundleName: bundleName, zipURL: zipURL)
            let zipData = try Data(contentsOf: zipURL)

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
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                        return (resp, Data(payload.utf8))
                    }
                    if s.contains("/resolve/main/\(zipName)") == true {
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
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
