import Foundation

public struct UnsupportedModelError: Error, LocalizedError, Sendable {
    public let backend: Backend
    public let model: String

    public var errorDescription: String? {
        return "Unsupported model '\(self.model)' for \(self.backend.rawValue)"
    }
}
