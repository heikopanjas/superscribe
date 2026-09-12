import Foundation

/// Named on-disk roots used across superscribe. Paths are intentionally
/// different per subsystem — do not collapse to a single cache root.
public enum SuperscribePaths {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var overrideFluidAudioModelsDirectory: URL?
        var overrideWhisperModelCacheDirectory: URL?
    }

    /// Task-local override (parallel-safe); checked before the static override.
    @TaskLocal static var taskFluidAudioModelsDirectory: URL?
    @TaskLocal static var taskWhisperModelCacheDirectory: URL?

    /// Override for unit tests; nil uses the real FluidAudio models directory.
    internal static var overrideFluidAudioModelsDirectory: URL? {
        get { return Self.testState[\.overrideFluidAudioModelsDirectory] }
        set { Self.testState[\.overrideFluidAudioModelsDirectory] = newValue }
    }
    /// Override for unit tests; nil uses the real whisper model cache directory.
    internal static var overrideWhisperModelCacheDirectory: URL? {
        get { return Self.testState[\.overrideWhisperModelCacheDirectory] }
        set { Self.testState[\.overrideWhisperModelCacheDirectory] = newValue }
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

    /// `~/Library/Caches/superscribe/whisper`
    public static func whisperModelCacheDirectory() -> URL {
        if let taskWhisperModelCacheDirectory = Self.taskWhisperModelCacheDirectory {
            return taskWhisperModelCacheDirectory
        }
        if let overrideWhisperModelCacheDirectory = Self.overrideWhisperModelCacheDirectory {
            return overrideWhisperModelCacheDirectory
        }
        let base = URL.cachesDirectory
        return base.appendingPathComponent("superscribe/whisper", isDirectory: true)
    }

    /// `~/Library/Application Support/FluidAudio/Models`
    public static func fluidAudioModelsDirectory() -> URL {
        if let taskFluidAudioModelsDirectory = Self.taskFluidAudioModelsDirectory {
            return taskFluidAudioModelsDirectory
        }
        if let overrideFluidAudioModelsDirectory = Self.overrideFluidAudioModelsDirectory {
            return overrideFluidAudioModelsDirectory
        }
        let base = URL.applicationSupportDirectory
        return
            base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}
