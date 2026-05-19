import Foundation
import Testing

@testable import SuperscribeKit

@Suite("HuggingFaceHub networking", .serialized, ResetSharedStateTrait())
struct HuggingFaceHubNetworkTests {

    private func tearDownMocks() {
        MockURLSessionHelpers.reset()
    }

    @Test func listAuthorReposUsesMockSession() async throws {
        let payload = """
            [{"id":"FluidInference/demo-coreml","lastModified":"2024-01-02T03:04:05Z"}]
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(payload.utf8))
            },
            { session in
                let repos = try await HuggingFaceHub.listAuthorRepos(
                    author: "FluidInference",
                    search: nil,
                    session: session
                )
                #expect(repos.count == 1)
                #expect(repos[0].id == "FluidInference/demo-coreml")
                #expect(repos[0].lastModified != nil)
            }
        )
    }

    @Test func repoInfoSuccess() async throws {
        let payload = """
            {"id":"ggerganov/whisper.cpp","lastModified":"2024-03-01T00:00:00Z","siblings":[
              {"rfilename":"ggml-base.bin","size":100}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(payload.utf8))
            },
            { session in
                let info = try await HuggingFaceHub.repoInfo(
                    repoId: "ggerganov/whisper.cpp",
                    session: session
                )
                #expect(info.id == "ggerganov/whisper.cpp")
                #expect(info.siblings.count == 1)
                #expect(info.siblings[0].rfilename == "ggml-base.bin")
            }
        )
    }

    @Test func http404MapsToHttpError() async throws {
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (resp, Data())
            },
            { session in
                await #expect(throws: HuggingFaceHub.Error.self) {
                    _ = try await HuggingFaceHub.repoInfo(repoId: "nope/nope", session: session)
                }
            }
        )
    }

    @Test func transportErrorFromFailedMock() async throws {
        try await MockURLSessionHelpers.withMockHandler(
            { _ in throw URLError(.notConnectedToInternet) },
            { session in
                await #expect(throws: HuggingFaceHub.Error.self) {
                    _ = try await HuggingFaceHub.repoInfo(repoId: "a/b", session: session)
                }
            }
        )
    }

    @Test func flexibleISO8601ParsesFractionalAndPlain() throws {
        let frac = try #require(HuggingFaceHub.flexibleISO8601("2024-05-01T12:34:56.789Z"))
        let plain = try #require(HuggingFaceHub.flexibleISO8601("2024-05-01T12:34:56Z"))
        #expect(frac.timeIntervalSinceReferenceDate > 0)
        #expect(plain.timeIntervalSinceReferenceDate > 0)

        let bad = HuggingFaceHub.flexibleISO8601("not-a-date")
        #expect(bad == nil)
    }

    @Test func decodingErrorWrapsPayload() async throws {
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(#"{"id":"x","lastModified":123,"siblings":[]}"#.utf8))
            },
            { session in
                await #expect(throws: HuggingFaceHub.Error.self) {
                    _ = try await HuggingFaceHub.repoInfo(
                        repoId: "ggerganov/whisper.cpp",
                        session: session
                    )
                }
            }
        )
    }
}
