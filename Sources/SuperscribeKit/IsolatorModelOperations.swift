import Foundation

/// Injectable boundary for upstream verified assets; lifecycle policy stays in ModelInstaller.
internal struct IsolatorModelOperations: Sendable {
    internal let validate: @Sendable (IsolatorModel, URL) throws -> Void
    internal let download: @Sendable (IsolatorModel, URL, @escaping @Sendable (DownloadProgress) -> Void) async throws -> Void
    internal var downloadSize: @Sendable (IsolatorModel) -> Int64 = { _ in 0 }
}
