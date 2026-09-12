import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ModelDownloader.streamBytes", .serialized, ResetSharedStateTrait())
struct ModelDownloaderTests {
    private func tempDest() -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("stream-\(UUID().uuidString).bin")
    }

    @Test func writesAllBytes() async throws -> Void {
        let dest = self.tempDest()
        defer { try? FileManager.default.removeItem(at: dest) }
        let payload: [UInt8] = Array(repeating: 0xAB, count: 128 * 1024 + 17)
        let stream = AsyncStream<UInt8> { continuation in
            for b in payload { continuation.yield(b) }
            continuation.finish()
        }

        let written = try await ModelDownloader.streamBytes(
            from: stream,
            to: dest,
            sourceURL: (try #require(URL(string: "https://example.com/file"))),
            expectedSize: Int64(payload.count)
        )

        #expect(written == Int64(payload.count))
        let data = try Data(contentsOf: dest)
        #expect(data.count == payload.count)
    }

    @Test func rejectsTruncatedDownload() async throws -> Void {
        let dest = self.tempDest()
        defer { try? FileManager.default.removeItem(at: dest) }
        let stream = AsyncStream<UInt8> { continuation in
            continuation.yield(1)
            continuation.finish()
        }

        await #expect(throws: ModelInstallationError.self) {
            _ = try await ModelDownloader.streamBytes(
                from: stream,
                to: dest,
                sourceURL: (try #require(URL(string: "https://example.com/file"))),
                expectedSize: 100
            )
        }
    }

    @Test func rejectsUnwritableDestination() async throws -> Void {
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("block-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blockingFile)
        defer { try? FileManager.default.removeItem(at: blockingFile) }
        let dest = blockingFile.appendingPathComponent("nested.bin")
        let stream = AsyncStream<UInt8> { $0.finish() }

        await #expect(throws: ModelInstallationError.self) {
            _ = try await ModelDownloader.streamBytes(
                from: stream,
                to: dest,
                sourceURL: (try #require(URL(string: "https://example.com/file"))),
                expectedSize: nil
            )
        }
    }

    @Test func httpSuccessRange() throws -> Void {
        let ok =
            (try #require(
                HTTPURLResponse(
                    url: (try TestHelpers.requireValue(URL(string: "https://example.com"))),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )))
        #expect(ok.isSuccess == true)

        let missing =
            (try #require(
                HTTPURLResponse(
                    url: (try TestHelpers.requireValue(URL(string: "https://example.com"))),
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )))
        #expect(missing.isSuccess == false)
    }
}
