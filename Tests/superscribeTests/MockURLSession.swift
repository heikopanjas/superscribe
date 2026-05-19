import Foundation

/// URLProtocol stub that calls a handler for every matched request.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        handler != nil && request.url != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, request.url != nil else {
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

extension URLSession {
    /// Ephemeral session that consults `MockURLProtocol` before system protocols.
    static func mocked() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }
}

enum MockURLSessionHelpers {
    static func reset() {
        MockURLProtocol.handler = nil
    }

    /// Holds the mock handler for the duration of `body`.
    static func withMockHandler<T>(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data),
        _ body: () async throws -> T
    ) async rethrows -> T {
        MockURLProtocol.handler = handler
        defer { MockURLProtocol.handler = nil }
        return try await body()
    }

    /// Handler picks the first route whose prefix matches `URLRequest.url.absoluteString`.
    static func registerRoutes(_ routes: [(prefix: String, statusCode: Int, data: Data)]) {
        MockURLProtocol.handler = { req in
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
        }
    }

    /// Convenience for JSON UTF-8 payloads.
    static func registerJSON(prefix: String, statusCode: Int = 200, json: String) {
        registerRoutes([(prefix: prefix, statusCode: statusCode, data: Data(json.utf8))])
    }
}
