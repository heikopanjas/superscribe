import FluidAudio
import Foundation

/// Internal flags used by unit tests to exercise error paths that are
/// impractical to trigger through real AVFoundation / filesystem failures.
enum SuperscribeKitTestHooks {
    nonisolated(unsafe) static var forceAudioPreparerFastPathBufferFailure = false
    nonisolated(unsafe) static var forceAudioPreparerCachedBufferFailure = false
    nonisolated(unsafe) static var forceAudioPreparerConverterCreationFailure = false
    nonisolated(unsafe) static var forceAudioPreparerOutputBufferFailure = false
    nonisolated(unsafe) static var forceAudioPreparerInputBufferFailure = false
    nonisolated(unsafe) static var forceAudioPreparerConversionError: String?
    nonisolated(unsafe) static var forceAudioPreparerEndOfStreamImmediately = false
    nonisolated(unsafe) static var forceAudioPreparerZeroFrameRead = false
    nonisolated(unsafe) static var forceAudioPreparerSecondPullEndOfStream = false
    nonisolated(unsafe) static var forceAudioPreparerMarkEndBeforeSecondPull = false
    nonisolated(unsafe) static var forceAudioPreparerConverterNativeError = false

    nonisolated(unsafe) static var forceAnalyzerMonoFormatFailure = false
    nonisolated(unsafe) static var forceAnalyzerSourceBufferFailure = false
    nonisolated(unsafe) static var forceAnalyzerReadIntoFailure = false
    nonisolated(unsafe) static var forceAnalyzerConverterCreationFailure = false
    nonisolated(unsafe) static var forceAnalyzerConversionError: Error?
    nonisolated(unsafe) static var forceAnalyzerSecondInputEndOfStream = false
    nonisolated(unsafe) static var forceAnalyzerChunkedInput = false
    nonisolated(unsafe) static var forceAnalyzerSmallMonoBuffer = false
    nonisolated(unsafe) static var forceAnalyzerInjectConversionError = false
    nonisolated(unsafe) static var forceAnalyzerNilMonoChannel = false
    nonisolated(unsafe) static var forceAnalyzerSimulatedConversionError: NSError?
    nonisolated(unsafe) static var forceAnalyzerBadConverterStatus = false
    nonisolated(unsafe) static var forceAnalyzerConversionStatusError = false

    nonisolated(unsafe) static var forceCacheStoreWriteBufferFailure = false
    nonisolated(unsafe) static var forceCacheStoreWriteError: Error?
    nonisolated(unsafe) static var forceCacheStoreMidWriteFailure = false
    nonisolated(unsafe) static var forceCacheStoreAtomicReplaceFailure = false
    nonisolated(unsafe) static var forceCacheStoreOpenFailure = false
    nonisolated(unsafe) static var forceCacheKeyAttributeParseFailure = false
    nonisolated(unsafe) static var forceCacheKeyAttributeGuardFailure = false

    nonisolated(unsafe) static var forceModelInstallerAtomicReplaceFailure = false
    nonisolated(unsafe) static var forceModelInstallerPreflightVolumeLookupFailure = false
    nonisolated(unsafe) static var forceModelInstallerPreflightVolumeUnknown = false

    nonisolated(unsafe) static var forceModelDownloaderFileHandleFailure = false

    nonisolated(unsafe) static var forceParakeetDirectorySizeEnumeratorFailure = false
    nonisolated(unsafe) static var forceParakeetDirectorySizeNilEnumerator = false
    nonisolated(unsafe) static var forceContentsOfDirectoryFailure = false
    nonisolated(unsafe) static var forceUnzipInvalidStderr = false
    nonisolated(unsafe) static var forceEncoderBundleEnumeratorNil = false

    /// When set, replaces FluidAudio disk load in `ensureLoaded` before `materializeFromDisk`.
    nonisolated(unsafe) static var parakeetMaterializeSession: (@Sendable (URL, AsrModelVersion) async throws -> any ParakeetASRSession)?

    /// When set, replaces the body of `materializeFromDisk` after the status line (no HF downloads).
    nonisolated(unsafe) static var parakeetMaterializeFromDiskStub: (@Sendable (URL, AsrModelVersion) async throws -> any ParakeetASRSession)?

    /// When set, replaces `AsrModels.load` inside `materializeFromDiskUsingFluidAudio`.
    nonisolated(unsafe) static var parakeetAsrModelsLoad: (@Sendable (URL, AsrModelVersion) async throws -> AsrModels)?

    /// When set, replaces `AsrManager.loadModels` inside `loadParakeetModelsIntoManager`.
    nonisolated(unsafe) static var parakeetAsrManagerLoadModels: (@Sendable (AsrManager) async throws -> Void)?

    /// Runs after `requireInstalled` succeeds, skipping FluidAudio load.
    nonisolated(unsafe) static var parakeetLoadAfterInstalledCheck: (@Sendable () async throws -> any ParakeetASRSession)?

    /// Clears all hook flags (used by the test harness between tests).
    static func resetAll() {
        forceAudioPreparerFastPathBufferFailure = false
        forceAudioPreparerCachedBufferFailure = false
        forceAudioPreparerConverterCreationFailure = false
        forceAudioPreparerOutputBufferFailure = false
        forceAudioPreparerInputBufferFailure = false
        forceAudioPreparerConversionError = nil
        forceAudioPreparerEndOfStreamImmediately = false
        forceAudioPreparerZeroFrameRead = false
        forceAudioPreparerSecondPullEndOfStream = false
        forceAudioPreparerMarkEndBeforeSecondPull = false
        forceAudioPreparerConverterNativeError = false
        forceAnalyzerMonoFormatFailure = false
        forceAnalyzerSourceBufferFailure = false
        forceAnalyzerReadIntoFailure = false
        forceAnalyzerConverterCreationFailure = false
        forceAnalyzerConversionError = nil
        forceAnalyzerSecondInputEndOfStream = false
        forceAnalyzerChunkedInput = false
        forceAnalyzerSmallMonoBuffer = false
        forceAnalyzerInjectConversionError = false
        forceAnalyzerNilMonoChannel = false
        forceAnalyzerSimulatedConversionError = nil
        forceAnalyzerBadConverterStatus = false
        forceAnalyzerConversionStatusError = false
        forceCacheStoreWriteBufferFailure = false
        forceCacheStoreWriteError = nil
        forceCacheStoreMidWriteFailure = false
        forceCacheStoreAtomicReplaceFailure = false
        forceCacheStoreOpenFailure = false
        forceCacheKeyAttributeParseFailure = false
        forceCacheKeyAttributeGuardFailure = false
        forceModelInstallerAtomicReplaceFailure = false
        forceModelInstallerPreflightVolumeLookupFailure = false
        forceModelInstallerPreflightVolumeUnknown = false
        forceModelDownloaderFileHandleFailure = false
        forceParakeetDirectorySizeEnumeratorFailure = false
        forceParakeetDirectorySizeNilEnumerator = false
        forceContentsOfDirectoryFailure = false
        forceUnzipInvalidStderr = false
        forceEncoderBundleEnumeratorNil = false
        parakeetMaterializeSession = nil
        parakeetMaterializeFromDiskStub = nil
        parakeetAsrModelsLoad = nil
        parakeetAsrManagerLoadModels = nil
        parakeetLoadAfterInstalledCheck = nil
    }
}
