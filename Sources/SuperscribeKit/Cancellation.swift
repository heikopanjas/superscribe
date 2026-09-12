import Foundation

internal enum Cancellation {
    internal static func propagate(_ error: any Error) throws -> Void {
        if (error is CancellationError) == true || (error as? URLError)?.code == .cancelled || Task.isCancelled == true { throw CancellationError() }
    }
}
