import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Whisper repository fixture", .serialized, ResetSharedStateTrait())
struct WhisperDownloadFixtureTests {
    @Test func rejectsUnconfiguredRequests() throws -> Void {
        let fixture = try WhisperDownloadFixture()
        let repo = fixture.model.repoId
        let urls = [
            "https://unexpected.invalid/api/models/\(repo)?blobs=true",
            "http://huggingface.co/api/models/\(repo)?blobs=true",
            "https://huggingface.co/api/models/\(repo)",
            "https://huggingface.co/api/models/\(repo)?blobs=true&extra=true",
            "https://huggingface.co/api/models/another-repository?blobs=true",
            "https://huggingface.co/\(repo)/resolve/main/undeclared.bin"
        ]
        for text in urls {
            let request = URLRequest(url: try #require(URL(string: text)))
            #expect(throws: URLError.self) { _ = try fixture.response(to: request) }
        }
        var request = URLRequest(url: try #require(URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")))
        request.httpMethod = "POST"
        #expect(throws: URLError.self) { _ = try fixture.response(to: request) }
    }

    @Test func metadataHTTPFailureReachesClient() async throws -> Void {
        let fixture = try WhisperDownloadFixture(metadataStatus: 503)
        try await fixture.withSession { session in
            do {
                _ = try await HuggingFaceHub.repoInfo(repoId: fixture.model.repoId, session: session)
                Issue.record("Expected repository metadata failure")
            }
            catch HuggingFaceHub.Error.http(let status, _) {
                #expect(status == 503)
            }
        }
    }

    @Test func downloadHTTPFailureReachesClient() async throws -> Void {
        let fixture = try WhisperDownloadFixture(binary: .init(Data("binary".utf8), status: 503))
        try await fixture.withSession { session in
            do {
                try await ModelDownloader.downloadFile(model: fixture.model, into: fixture.binaryURL, session: session, onProgress: { _ in })
                Issue.record("Expected model download failure")
            }
            catch ModelInstallationError.httpError(let status, _) {
                #expect(status == 503)
            }
            #expect(FileManager.default.fileExists(atPath: fixture.binaryURL.path) == false)
        }
    }
}
