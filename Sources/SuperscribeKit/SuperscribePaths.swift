import Foundation

/// Named on-disk roots used across superscribe. Paths are intentionally
/// different per subsystem — do not collapse to a single cache root.
public enum SuperscribePaths {
    /// Task-local override (parallel-safe); checked before the static override.
    @TaskLocal static var taskFluidAudioModelsDirectory: URL?
    @TaskLocal static var taskWhisperModelCacheDirectory: URL?

    /// Override for unit tests; nil uses the real FluidAudio models directory.
    nonisolated(unsafe) static var overrideFluidAudioModelsDirectory: URL?
    /// Override for unit tests; nil uses the real whisper model cache directory.
    nonisolated(unsafe) static var overrideWhisperModelCacheDirectory: URL?

    /// `~/.config/superscribe`
    public static func userConfigDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/superscribe", isDirectory: true)
    }

    /// `~/.cache/superscribe`
    public static func catalogCacheDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/superscribe", isDirectory: true)
    }

    /// `~/.cache/superscribe/audio`
    public static func audioCacheRoot() -> URL {
        catalogCacheDirectory().appendingPathComponent("audio", isDirectory: true)
    }

    /// `~/Library/Caches/superscribe/whisper`
    public static func whisperModelCacheDirectory() -> URL {
        if let taskWhisperModelCacheDirectory {
            return taskWhisperModelCacheDirectory
        }
        if let overrideWhisperModelCacheDirectory {
            return overrideWhisperModelCacheDirectory
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("superscribe/whisper", isDirectory: true)
    }

    /// `~/Library/Application Support/FluidAudio/Models`
    public static func fluidAudioModelsDirectory() -> URL {
        if let taskFluidAudioModelsDirectory {
            return taskFluidAudioModelsDirectory
        }
        if let overrideFluidAudioModelsDirectory {
            return overrideFluidAudioModelsDirectory
        }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return
            base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}
