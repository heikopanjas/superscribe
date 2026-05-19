import Foundation

extension HTTPURLResponse {
    /// `true` when the status code is in 200…299.
    public var isSuccess: Bool {
        (200 ..< 300).contains(statusCode)
    }
}

enum HTTPValidation {
    static func requireSuccess(_ response: URLResponse, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.isSuccess == false {
            throw ModelInstallationError.httpError(status: http.statusCode, url: url)
        }
    }
}
