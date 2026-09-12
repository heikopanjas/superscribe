import Foundation

enum MockURLSessionHelpers {
    static func makeSession(sessionID: String, delegate: (any URLSessionDelegate)? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [MockURLProtocol.sessionIDHeader: sessionID]
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    static func resetAll() -> Void {
        MockURLProtocol.resetAll()
    }

    /// Holds the mock handler for the duration of `body`.
    @discardableResult
    static func withMockHandler<T>(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data),
        _ body: (URLSession) async throws -> T
    ) async rethrows -> T {
        let sessionID = UUID().uuidString
        MockURLProtocol.register(handler: handler, forSessionID: sessionID)
        let lifetime = MockSessionLifetime()
        let session = Self.makeSession(sessionID: sessionID, delegate: lifetime)
        do {
            let result = try await body(session)
            session.invalidateAndCancel()
            await lifetime.invalidated.wait()
            MockURLProtocol.unregister(sessionID: sessionID)
            return result
        }
        catch {
            session.invalidateAndCancel()
            await lifetime.invalidated.wait()
            MockURLProtocol.unregister(sessionID: sessionID)
            throw error
        }
    }

    /// Legacy name used by a few suites.
    static func reset() -> Void {
        Self.resetAll()
    }
}
