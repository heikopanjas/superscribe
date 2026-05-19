import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ModelDownloader networking", .serialized)
struct ModelDownloaderNetworkTests {

    private final class ProgressList: @unchecked Sendable {
        var ticks: [DownloadProgress] = []
    }

    private final class LastProgress: @unchecked Sendable {
        var value: DownloadProgress?
    }

    private final class RepoChunkLog: @unchecked Sendable {
        var chunks: [(Int64, Int64?)] = []
    }

    private func tearDown() {
        MockURLSessionHelpers.reset()
    }

    @Test func downloadMultiFileRespectsSubpath() async throws {
        let repoId = "FluidInference/subpath-demo"
        let repoURL = URL(string: "https://huggingface.co/\(repoId)")!
        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"weights/a.bin","size":3},
              {"rfilename":"weights/b.bin","size":4},
              {"rfilename":"README.md","size":2}
            ]}
            """

        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: nil, headerFields: nil
                    )!
                    return (resp, Data(repoPayload.utf8))
                }
                if s.contains("/resolve/main/weights/a.bin") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data("AAA".utf8))
                }
                if s.contains("/resolve/main/weights/b.bin") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data("BBBB".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            {
                try await TestHelpers.withTempDirectory(prefix: "mdl-subpath") { staging in
                    let model = RemoteModelInfo(
                        id: "demo",
                        repoId: repoId,
                        subpath: "weights/",
                        totalSizeBytes: 7,
                        fileCount: 2,
                        lastModified: nil,
                        repoURL: repoURL
                    )
                    let sink = ProgressList()
                    try await ModelDownloader.download(
                        model: model,
                        backend: .parakeet,
                        into: staging,
                        session: URLSession.mocked(),
                        onProgress: { sink.ticks.append($0) }
                    )

                    let a = staging.appendingPathComponent("a.bin")
                    let b = staging.appendingPathComponent("b.bin")
                    #expect(FileManager.default.fileExists(atPath: a.path) == true)
                    #expect(FileManager.default.fileExists(atPath: b.path) == true)
                    #expect(try String(contentsOf: a) == "AAA")
                    #expect(try String(contentsOf: b) == "BBBB")
                    #expect(sink.ticks.isEmpty == false)
                }
            }
        )
    }

    @Test func downloadFileWritesWhisperBin() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-tiny.bin","size":5}
            ]}
            """

        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(repoPayload.utf8))
                }
                if s.contains("/resolve/main/ggml-tiny.bin") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data("hello".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            {
                try await TestHelpers.withTempDirectory(prefix: "mdl-bin") { dir in
                    let dest = dir.appendingPathComponent("tiny.bin.staging")
                    let model = RemoteModelInfo(
                        id: "tiny",
                        repoId: repoId,
                        subpath: nil,
                        totalSizeBytes: 5,
                        fileCount: 1,
                        lastModified: nil,
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    let lastBox = LastProgress()
                    try await ModelDownloader.downloadFile(
                        model: model,
                        into: dest,
                        session: URLSession.mocked(),
                        onProgress: { lastBox.value = $0 }
                    )
                    #expect(try String(contentsOf: dest) == "hello")
                    #expect(lastBox.value?.bytesCompleted == 5)
                }
            }
        )
    }

    @Test func downloadRepoFileStreamsBytes() async throws {
        let repoId = "org/enc-demo"
        let file = "bundle.zip"
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/resolve/main/\(file)") == true {
                    let resp = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (resp, Data([0x50, 0x4B]))
                }
                throw URLError(.unsupportedURL)
            },
            {
                try await TestHelpers.withTempDirectory(prefix: "mdl-repo-file") { dir in
                    let dest = dir.appendingPathComponent(file)
                    let log = RepoChunkLog()
                    try await ModelDownloader.downloadRepoFile(
                        repoId: repoId,
                        rfilename: file,
                        into: dest,
                        expectedSize: 2,
                        session: URLSession.mocked(),
                        onProgress: { done, total in
                            log.chunks.append((done, total))
                        }
                    )
                    #expect(try Data(contentsOf: dest).count == 2)
                    #expect(log.chunks.isEmpty == false)
                }
            }
        )
    }

    @Test func downloadHttpErrorUsesHttpStatus() async throws {
        let repoId = "org/x"
        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"a.bin","size":3}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(repoPayload.utf8))
                }
                let resp = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (resp, Data())
            },
            {
                try await TestHelpers.withTempDirectory(prefix: "mdl-http") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        subpath: nil,
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.download(
                            model: model,
                            backend: .parakeet,
                            into: staging,
                            session: URLSession.mocked(),
                            onProgress: { _ in }
                        )
                    }
                }
            }
        )
    }

    @Test func downloadEmptyFilteredFileListThrows() async throws {
        let repoId = "org/empty-filter"
        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"root.txt","size":1}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(repoPayload.utf8))
            },
            {
                try await TestHelpers.withTempDirectory(prefix: "mdl-empty") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        subpath: "missing-prefix/",
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.download(
                            model: model,
                            backend: .parakeet,
                            into: staging,
                            session: URLSession.mocked(),
                            onProgress: { _ in }
                        )
                    }
                }
            }
        )
    }
}
