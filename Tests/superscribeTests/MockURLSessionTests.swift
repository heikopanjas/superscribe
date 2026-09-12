import Foundation
import Testing

@Suite("Mock networking fails closed")
struct MockURLSessionTests {
    @Test func missingHandlerFailsRequest() async throws -> Void {
        let session = MockURLSessionHelpers.makeSession(sessionID: UUID().uuidString)
        defer { session.invalidateAndCancel() }
        let url = try #require(URL(string: "https://unregistered.invalid/test"))
        await #expect(throws: URLError.self) {
            _ = try await session.data(from: url)
        }
    }

    @Test func requestsWithoutRoutingHeaderAreIntercepted() throws -> Void {
        let url = try #require(URL(string: "https://unregistered.invalid/test"))
        #expect(MockURLProtocol.canInit(with: URLRequest(url: url)) == true)
    }
}
