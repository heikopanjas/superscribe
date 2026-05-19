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

    /// When set, replaces FluidAudio disk load in `ensureLoaded`.
    nonisolated(unsafe) static var parakeetMaterializeSession: (@Sendable (URL, AsrModelVersion) async throws -> any ParakeetASRSession)?

    /// Runs after `requireInstalled` succeeds, skipping FluidAudio load.
    nonisolated(unsafe) static var parakeetLoadAfterInstalledCheck: (@Sendable () async throws -> any ParakeetASRSession)?
}
