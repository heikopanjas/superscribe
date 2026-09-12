import Foundation

/// Persisted user preferences for superscribe.
///
/// Stored as JSON at `~/.config/superscribe/config.json`.
public struct UserConfig: Codable, Sendable {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var overrideConfigFileURL: URL?
    }

    /// Per-backend default model overrides (keyed by `Backend.rawValue`).
    public var defaultModels: [String: String]
    /// User's preferred default backend (nil = built-in default `.parakeet`).
    public var defaultBackend: String?

    public init(defaultModels: [String: String] = [:], defaultBackend: String? = nil) {
        self.defaultModels = defaultModels
        self.defaultBackend = defaultBackend
    }

    // MARK: - Persistence

    public static let configDirectory: URL = SuperscribePaths.userConfigDirectory()

    /// Override for unit tests (nil = default `~/.config/superscribe/config.json`).
    internal static var overrideConfigFileURL: URL? {
        get { return Self.testState[\.overrideConfigFileURL] }
        set { Self.testState[\.overrideConfigFileURL] = newValue }
    }
    /// Task-local override (parallel-safe); checked before the static override.
    @TaskLocal static var taskOverrideConfigFileURL: URL?

    public static var configFileURL: URL {
        if let taskOverrideConfigFileURL = Self.taskOverrideConfigFileURL {
            return taskOverrideConfigFileURL
        }
        if let overrideConfigFileURL = Self.overrideConfigFileURL {
            return overrideConfigFileURL
        }
        return Self.configDirectory.appendingPathComponent("config.json")
    }

    public static func load() throws -> UserConfig {
        guard FileManager.default.fileExists(atPath: Self.configFileURL.path) == true else { return UserConfig() }
        let data = try Data(contentsOf: Self.configFileURL)
        return try JSONCoding.catalogDecoder().decode(UserConfig.self, from: data)
    }

    /// Updates preferences under a cross-process lock without losing other writers' fields.
    public static func update(_ mutation: @Sendable @escaping (inout UserConfig) throws -> Void) async throws -> Void {
        let url = Self.configFileURL
        let locks = FileTransaction.lockOperation
        try await FileTransaction.worker.run { _ in
            try Self.$taskOverrideConfigFileURL.withValue(url) {
                try FileTransaction.$lockOperation.withValue(locks) {
                    try FileTransaction.withLock(for: url) {
                        var configuration = try Self.load()
                        try mutation(&configuration)
                        try configuration.save()
                    }
                }
            }
        }
    }

    public func save() throws -> Void {
        try FileManager.default.createDirectory(
            at: Self.configFileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONCoding.configEncoder().encode(self)
        try data.write(to: Self.configFileURL, options: .atomic)
    }

    /// Returns the user's chosen default model for a backend, or `nil`
    /// if no override is set.
    public func defaultModel(for backend: Backend) -> String? {
        return self.defaultModels[backend.rawValue]
    }

    /// Sets the default model for a backend.
    public mutating func setDefaultModel(_ model: String, for backend: Backend) -> Void {
        self.defaultModels[backend.rawValue] = model
        return
    }

    /// Returns the user's preferred backend, or the built-in default.
    public func resolvedDefaultBackend() -> Backend {
        if let raw = self.defaultBackend, let backend = Backend(rawValue: raw) {
            return backend
        }
        return .parakeet
    }

    /// Sets the user's preferred default backend.
    public mutating func setDefaultBackend(_ backend: Backend) -> Void {
        self.defaultBackend = backend.rawValue
        return
    }
}
