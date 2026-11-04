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
    /// User's preferred vocal-isolation backend (nil = built-in HTDemucs).
    public var defaultIsolatorBackend: String?
    /// User's preferred speaker-diarization backend (nil = built-in Nemotron).
    public var defaultDiarizerBackend: String?

    public init(defaultModels: [String: String] = [:], defaultBackend: String? = nil, defaultIsolatorBackend: String? = nil, defaultDiarizerBackend: String? = nil) {
        self.defaultModels = defaultModels
        self.defaultBackend = defaultBackend
        self.defaultIsolatorBackend = defaultIsolatorBackend
        self.defaultDiarizerBackend = defaultDiarizerBackend
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
        return Self.resolveBackend(self.defaultBackend, default: Backend.parakeet)
    }

    public func resolvedDefaultIsolatorBackend() -> IsolatorBackend {
        return Self.resolveBackend(self.defaultIsolatorBackend, default: IsolatorBackend.htdemucs)
    }

    public func resolvedDefaultDiarizerBackend() -> DiarizerBackend {
        return Self.resolveBackend(self.defaultDiarizerBackend, default: DiarizerBackend.nemotron)
    }

    /// Sets the user's preferred default backend.
    public mutating func setDefaultBackend(_ backend: Backend) -> Void {
        self.defaultBackend = backend.rawValue
        return
    }

    public mutating func setDefaultIsolatorBackend(_ backend: IsolatorBackend) -> Void {
        self.defaultIsolatorBackend = backend.rawValue
    }

    public mutating func setDefaultDiarizerBackend(_ backend: DiarizerBackend) -> Void {
        self.defaultDiarizerBackend = backend.rawValue
    }

    private static func resolveBackend<B: RawRepresentable>(_ rawValue: String?, default fallback: B) -> B where B.RawValue == String {
        if let rawValue, let backend = B(rawValue: rawValue) { return backend }
        return fallback
    }
}
