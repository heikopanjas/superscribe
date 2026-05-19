import Foundation

/// Persisted user preferences for superscribe.
///
/// Stored as JSON at `~/.config/superscribe/config.json`.
public struct UserConfig: Codable, Sendable {
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
    nonisolated(unsafe) static var overrideConfigFileURL: URL?
    /// Task-local override (parallel-safe); checked before the static override.
    @TaskLocal static var taskOverrideConfigFileURL: URL?

    public static var configFileURL: URL {
        if let taskOverrideConfigFileURL {
            return taskOverrideConfigFileURL
        }
        if let overrideConfigFileURL {
            return overrideConfigFileURL
        }
        return configDirectory.appendingPathComponent("config.json")
    }

    public static func load() -> UserConfig {
        guard let data = try? Data(contentsOf: configFileURL),
            let config = try? JSONCoding.catalogDecoder().decode(UserConfig.self, from: data)
        else {
            return UserConfig()
        }
        return config
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: Self.configDirectory, withIntermediateDirectories: true
        )
        let data = try JSONCoding.configEncoder().encode(self)
        try data.write(to: Self.configFileURL, options: .atomic)
    }

    /// Returns the user's chosen default model for a backend, or `nil`
    /// if no override is set.
    public func defaultModel(for backend: Backend) -> String? {
        defaultModels[backend.rawValue]
    }

    /// Sets the default model for a backend.
    public mutating func setDefaultModel(_ model: String, for backend: Backend) {
        defaultModels[backend.rawValue] = model
    }

    /// Returns the user's preferred backend, or the built-in default.
    public func resolvedDefaultBackend() -> Backend {
        if let raw = defaultBackend, let backend = Backend(rawValue: raw) {
            return backend
        }
        return .parakeet
    }

    /// Sets the user's preferred default backend.
    public mutating func setDefaultBackend(_ backend: Backend) {
        defaultBackend = backend.rawValue
    }
}
