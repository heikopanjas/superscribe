import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - ModelDownloader

@Suite("ModelDownloader extended", .serialized, ResetSharedStateTrait())
struct ModelDownloaderExtendedTests {
    @Test func downloadProgressFractionNilWhenTotalUnknown() throws -> Void {
        let p = DownloadProgress(
            modelId: "m",
            backend: .parakeet,
            currentFile: "a",
            filesCompleted: 0,
            filesTotal: 1,
            bytesCompleted: 10,
            bytesTotal: nil,
            bytesPerSecond: nil
        )
        #expect(p.fraction == nil)
        let zero = DownloadProgress(
            modelId: "m",
            backend: .parakeet,
            currentFile: "a",
            filesCompleted: 0,
            filesTotal: 1,
            bytesCompleted: 0,
            bytesTotal: 0,
            bytesPerSecond: nil
        )
        #expect(zero.fraction == nil)
    }

    @Test func downloadFileBinNotFoundThrows() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"README.md","size":1}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(repoPayload.utf8))
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-missing-bin") { dir in
                    let model = RemoteModelInfo(
                        id: "missing",
                        repoId: repoId,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.downloadFile(
                            model: model,
                            into: dir.appendingPathComponent("x.bin"),
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            }
        )
    }

    @Test func downloadRepoFileHttpError() async throws -> Void {
        _ = try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)))
                return (resp, Data())
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-http") { dir in
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.downloadRepoFile(
                            repoId: "org/repo",
                            rfilename: "file.bin",
                            into: dir.appendingPathComponent("file.bin"),
                            expectedSize: 1,
                            session: session,
                            onProgress: nil
                        )
                    }
                }
            }
        )
        return
    }

    @Test func streamBytesInvokesOnChunkForLargePayload() async throws -> Void {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: dest) }
        let payload = Array(repeating: UInt8(0xCD), count: 65_536 + 100)
        let stream = AsyncStream<UInt8> { continuation in
            for b in payload { continuation.yield(b) }
            continuation.finish()
        }
        final class ChunkSum: @unchecked Sendable {
            var total: Int64 = 0
        }
        let sum = ChunkSum()
        _ = try await ModelDownloader.streamBytes(
            from: stream,
            to: dest,
            sourceURL: (try #require(URL(string: "https://example.com/big"))),
            expectedSize: Int64(payload.count)
        ) { chunk in
            sum.total += chunk
        }
        #expect(sum.total == Int64(payload.count))
    }

    @Test func downloadProgressFractionComputesRatio() throws -> Void {
        let p = DownloadProgress(
            modelId: "m",
            backend: .parakeet,
            currentFile: "a",
            filesCompleted: 0,
            filesTotal: 1,
            bytesCompleted: 50,
            bytesTotal: 100,
            bytesPerSecond: nil
        )
        #expect(p.fraction == 0.5)
    }

    @Test func downloadRepoFileNetworkError() async throws -> Void {
        _ = try await MockURLSessionHelpers.withMockHandler(
            { _ in throw URLError(.notConnectedToInternet) },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-net") { dir in
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.downloadRepoFile(
                            repoId: "org/repo",
                            rfilename: "file.bin",
                            into: dir.appendingPathComponent("file.bin"),
                            expectedSize: 1,
                            session: session,
                            onProgress: nil
                        )
                    }
                }
            }
        )
        return
    }

    @Test func downloadOneHttpErrorViaMultiFile() async throws -> Void {
        let repoId = "FluidInference/http-err"
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
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(repoPayload.utf8))
                }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 502, httpVersion: nil, headerFields: nil)))
                return (resp, Data())
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-one-http") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.download(
                            model: model,
                            backend: .parakeet,
                            into: staging,
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            }
        )
    }

    @Test func streamBytesCreateDirectoryFailure() async throws -> Void {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocked-\(UUID().uuidString)/nested/file.bin")
        let blocker = dest.deletingLastPathComponent().deletingLastPathComponent()
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let stream = AsyncStream<UInt8> { $0.finish() }
        await #expect(throws: ModelInstallationError.self) {
            _ = try await ModelDownloader.streamBytes(
                from: stream,
                to: dest,
                sourceURL: (try #require(URL(string: "https://example.com/x"))),
                expectedSize: nil
            )
        }
    }

    @Test func streamBytesCannotOpenDestinationFile() async throws -> Void {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("parentfile-\(UUID().uuidString)")
        try Data("x".utf8).write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let dest = parent.appendingPathComponent("child.bin")
        let stream = AsyncStream<UInt8> { $0.finish() }
        await #expect(throws: ModelInstallationError.self) {
            _ = try await ModelDownloader.streamBytes(
                from: stream,
                to: dest,
                sourceURL: (try #require(URL(string: "https://example.com/x"))),
                expectedSize: nil
            )
        }
    }

    @Test func streamBytesTransportError() async throws -> Void {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("err-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: dest) }
        struct FailingBytes: AsyncSequence {
            typealias Element = UInt8
            struct Iterator: AsyncIteratorProtocol {
                func next() async throws -> UInt8? {
                    throw URLError(.networkConnectionLost)
                }
            }
            func makeAsyncIterator() -> Iterator { return Iterator() }
        }
        await #expect(throws: ModelInstallationError.self) {
            _ = try await ModelDownloader.streamBytes(
                from: FailingBytes(),
                to: dest,
                sourceURL: (try #require(URL(string: "https://example.com/x"))),
                expectedSize: nil
            )
        }
    }
}
