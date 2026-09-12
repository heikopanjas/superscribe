import Foundation

public enum BackendTranscriberError: Error, CustomStringConvertible, Sendable {
    case unavailable(String)

    public var description: String {
        switch self {
            case .unavailable(let msg): return msg
        }
    }
}
