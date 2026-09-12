import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("HuggingFaceHub date decode", .serialized, ResetSharedStateTrait())
struct HuggingFaceHubDateDecodeTests {
    @Test func badDateStringThrowsDecodingError() async throws -> Void {
        let payload = """
            [{"id":"FluidInference/x","lastModified":"not-a-date"}]
            """
        _ = try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                await #expect(throws: HuggingFaceHub.Error.self) {
                    _ = try await HuggingFaceHub.listAuthorRepos(
                        author: "FluidInference",
                        search: nil,
                        session: session
                    )
                }
            }
        )
    }
}
