import Foundation

/// Coalesces concurrent async loads into a single in-flight task.
///
/// On success the value is cached. On failure the in-flight task is cleared so
/// callers can retry.
public actor LoadOnce<Value: Sendable> {
    private var cached: Value?
    private var loadingTask: Task<Value, any Error>?

    public init() {}

    public func get(_ load: @Sendable @escaping () async throws -> Value) async throws -> Value {
        if let cached {
            return cached
        }
        if let loadingTask {
            return try await loadingTask.value
        }

        let task = Task { try await load() }
        loadingTask = task
        defer { loadingTask = nil }

        let value = try await task.value
        cached = value
        return value
    }
}

enum ModelInstallSupport {
    /// Throws `ModelInstallationError.modelNotInstalled` when `path` is absent.
    public static func requireInstalled(at path: URL, modelId: String, backend: Backend) throws {
        guard FileManager.default.fileExists(atPath: path.path) == true else {
            throw ModelInstallationError.modelNotInstalled(model: modelId, backend: backend)
        }
    }
}
