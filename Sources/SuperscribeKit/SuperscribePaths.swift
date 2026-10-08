import Foundation

/// Named on-disk roots used across superscribe. Configuration lives in `~/.config/superscribe`;
/// the catalog, converted audio, and every downloaded model live under `~/.cache/superscribe`,
/// with models grouped as `models/<kind>/`.
public enum SuperscribePaths {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var overrideModelsDirectory: URL?
    }

    /// Task-local override (parallel-safe); checked before the static override.
    @TaskLocal static var taskModelsDirectory: URL?

    /// Override for unit tests; nil uses the real models directory.
    internal static var overrideModelsDirectory: URL? {
        get { return Self.testState[\.overrideModelsDirectory] }
        set { Self.testState[\.overrideModelsDirectory] = newValue }
    }

    /// `~/.config/superscribe`
    public static func userConfigDirectory() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/superscribe", isDirectory: true)
    }

    /// `~/.cache/superscribe`
    public static func catalogCacheDirectory() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/superscribe", isDirectory: true)
    }

    /// `~/.cache/superscribe/audio`
    public static func audioCacheRoot() -> URL {
        return Self.catalogCacheDirectory().appendingPathComponent("audio", isDirectory: true)
    }

    /// `~/.cache/superscribe/models`
    public static func modelsDirectory() -> URL {
        if let taskModelsDirectory = Self.taskModelsDirectory {
            return taskModelsDirectory
        }
        if let overrideModelsDirectory = Self.overrideModelsDirectory {
            return overrideModelsDirectory
        }
        return Self.catalogCacheDirectory().appendingPathComponent("models", isDirectory: true)
    }

    /// `~/.cache/superscribe/models/parakeet`; folder names match FluidAudio's `Repo.folderName`.
    public static func parakeetModelsDirectory() -> URL {
        return Self.modelsDirectory().appendingPathComponent("parakeet", isDirectory: true)
    }

    /// `~/.cache/superscribe/models/whisper`
    public static func whisperModelsDirectory() -> URL {
        return Self.modelsDirectory().appendingPathComponent("whisper", isDirectory: true)
    }

    /// `~/.cache/superscribe/models/diarizer`
    public static func diarizerModelsDirectory() -> URL {
        return Self.modelsDirectory().appendingPathComponent("diarizer", isDirectory: true)
    }
}
