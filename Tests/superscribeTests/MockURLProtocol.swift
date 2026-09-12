import Foundation

/// URLProtocol stub that routes requests using a per-session handler id carried
/// in a custom HTTP header (parallel-safe; no global handler slot).
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    static let sessionIDHeader = "X-Superscribe-Mock-Session-ID"

    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    private static let lock = NSLock()

    static func register(handler: @escaping Handler, forSessionID id: String) -> Void {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        Self.handlers[id] = handler
    }

    static func unregister(sessionID id: String) -> Void {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        Self.handlers.removeValue(forKey: id)
    }

    static func resetAll() -> Void {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        Self.handlers.removeAll()
    }

    private static func handler(forSessionID id: String) -> Handler? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return Self.handlers[id]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() -> Void {
        guard
            let id = self.request.value(forHTTPHeaderField: Self.sessionIDHeader),
            let handler = Self.handler(forSessionID: id),
            self.request.url != nil
        else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() -> Void {}
}
