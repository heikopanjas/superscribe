import Foundation

/// Minimal client over the public Hugging Face Hub JSON API.
///
/// No authentication, no on-disk caching (catalog persistence lives one
/// layer up in `CatalogStore`). Tolerates unknown response fields and
/// missing optional values.
public enum HuggingFaceHub {
    public enum Error: Swift.Error, CustomStringConvertible {
        case http(status: Int, url: URL)
        case transport(URLError)
        case decoding(DecodingError, url: URL)

        public var description: String {
            switch self {
                case .http(let status, let url):
                    return "HTTP \(status) from \(url.absoluteString)"
                case .transport(let err):
                    return "Network error: \(err.localizedDescription)"
                case .decoding(let err, let url):
                    return "Failed to decode response from \(url.absoluteString): \(err)"
            }
        }
    }

    // MARK: - Public response shapes

    /// One entry from `/api/models?author=…`.
    public struct HFRepo: Sendable, Decodable, Hashable {
        public let id: String
        public let lastModified: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case lastModified
        }
    }

    /// One file inside a repo's `siblings` array.
    public struct HFSibling: Sendable, Decodable, Hashable {
        public let rfilename: String
        public let size: Int64?

        public init(rfilename: String, size: Int64? = nil) {
            self.rfilename = rfilename
            self.size = size
        }
    }

    /// Detailed repo info from `/api/models/{repoId}`.
    public struct HFRepoInfo: Sendable, Decodable, Hashable {
        public let id: String
        public let lastModified: Date?
        public let siblings: [HFSibling]

        enum CodingKeys: String, CodingKey {
            case id
            case lastModified
            case siblings
        }
    }

    // MARK: - Endpoints

    /// `GET https://huggingface.co/api/models?author=…&search=…`
    public static func listAuthorRepos(
        author: String,
        search: String? = nil,
        session: URLSession = .shared
    ) async throws -> [HFRepo] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        var items: [URLQueryItem] = [URLQueryItem(name: "author", value: author)]
        if let search { items.append(URLQueryItem(name: "search", value: search)) }
        components.queryItems = items
        let url = components.url!
        let data = try await fetch(url, session: session)
        return try decode([HFRepo].self, from: data, url: url)
    }

    /// `GET https://huggingface.co/api/models/{repoId}` (siblings + lastModified).
    public static func repoInfo(
        repoId: String,
        session: URLSession = .shared
    ) async throws -> HFRepoInfo {
        let url = URL(string: "https://huggingface.co/api/models/\(repoId)")!
        let data = try await fetch(url, session: session)
        return try decode(HFRepoInfo.self, from: data, url: url)
    }

    // MARK: - Internals

    static let userAgent: String = "superscribe/0.1"

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.flexibleISO8601(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO 8601 date string, got '\(raw)'."
            )
        }
        return decoder
    }

    /// Parses ISO 8601 dates with or without fractional seconds.
    static func flexibleISO8601(_ s: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, url: URL) throws -> T {
        do {
            return try decoder().decode(T.self, from: data)
        }
        catch let err as DecodingError {
            throw Error.decoding(err, url: url)
        }
    }

    static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                throw Error.http(status: http.statusCode, url: url)
            }
            return data
        }
        catch let err as URLError {
            throw Error.transport(err)
        }
    }
}
