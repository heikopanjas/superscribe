import Foundation

/// URLProtocol stub that routes requests using a per-session handler id carried
/// in a custom HTTP header (parallel-safe; no global handler slot).
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    static let sessionIDHeader = "X-Superscribe-Mock-Session-ID"

    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    private static let lock = NSLock()

    static func register(handler: @escaping Handler, forSessionID id: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[id] = handler
    }

    static func unregister(sessionID id: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: id)
    }

    static func resetAll() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    private static func handler(forSessionID id: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[id]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let id = request.value(forHTTPHeaderField: sessionIDHeader) else { return false }
        return handler(forSessionID: id) != nil && request.url != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let id = request.value(forHTTPHeaderField: Self.sessionIDHeader),
            let handler = Self.handler(forSessionID: id),
            request.url != nil
        else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum MockURLSessionHelpers {
    static func makeSession(sessionID: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [MockURLProtocol.sessionIDHeader: sessionID]
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }

    static func resetAll() {
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
        defer { MockURLProtocol.unregister(sessionID: sessionID) }
        let session = makeSession(sessionID: sessionID)
        return try await body(session)
    }

    /// Handler picks the first route whose prefix matches `URLRequest.url.absoluteString`.
    static func registerRoutes(_ routes: [(prefix: String, statusCode: Int, data: Data)]) {
        let sessionID = UUID().uuidString
        MockURLProtocol.register(
            handler: { req in
                guard let url = req.url else {
                    throw URLError(.badURL)
                }
                let absolute = url.absoluteString
                guard
                    let route = routes.first(where: { absolute.hasPrefix($0.prefix) == true })
                else {
                    throw URLError(.unsupportedURL)
                }
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: route.statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, route.data)
            }, forSessionID: sessionID)
    }

    /// Convenience for JSON UTF-8 payloads.
    static func registerJSON(prefix: String, statusCode: Int = 200, json: String) {
        registerRoutes([(prefix: prefix, statusCode: statusCode, data: Data(json.utf8))])
    }

    /// Legacy name used by a few suites.
    static func reset() {
        resetAll()
    }
}
