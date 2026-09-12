import Foundation

/// Constructs URLs from decoded components so path content cannot become query syntax.
internal enum HTTPURL {
    internal static func make(host: String, path: String, query: [URLQueryItem] = [], scheme: String = "https") throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        if query.isEmpty == false { components.queryItems = query }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}
