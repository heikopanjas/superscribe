import Foundation

public struct InputValidationError: Error, LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { return self.message }
    internal init(_ message: String) { self.message = message }
}
