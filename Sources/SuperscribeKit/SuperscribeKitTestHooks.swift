import FluidAudio
import Foundation

/// Internal flags used by unit tests to exercise error paths that are
/// impractical to trigger through real AVFoundation / filesystem failures.
enum SuperscribeKitTestHooks {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var audioReadFailureAfterFrames: Int64?
        var audioConverterErrorWithoutDetails = false
        var loadWaiterWillRegister: (@Sendable () -> Void)?
        var forceCacheStoreWriteBufferFailure = false
        var forceCacheStoreWriteError: Error?
        var forceCacheStoreMidWriteFailure = false
        var forceCacheStoreAtomicReplaceFailure = false
        var forceCacheStoreOpenFailure = false
        var forceCacheKeyAttributeParseFailure = false
        var forceCacheKeyAttributeGuardFailure = false
        var forceModelInstallerAtomicReplaceFailure = false
        var forceModelInstallerPreflightVolumeLookupFailure = false
        var forceModelInstallerPreflightVolumeUnknown = false
        var forceModelDownloaderFileHandleFailure = false
        var forceParakeetDirectorySizeEnumeratorFailure = false
        var forceParakeetDirectorySizeNilEnumerator = false
        var forceContentsOfDirectoryFailure = false
        var forceUnzipInvalidStderr = false
        var forceEncoderBundleEnumeratorNil = false
        var parakeetMaterializeSession: (@Sendable (URL, AsrModelVersion) async throws -> any ParakeetASRSession)?
        var parakeetMaterializeFromDiskStub: (@Sendable (URL, AsrModelVersion) async throws -> any ParakeetASRSession)?
        var parakeetAsrModelsLoad: (@Sendable (URL, AsrModelVersion) async throws -> AsrModels)?
        var parakeetAsrManagerLoadModels: (@Sendable (AsrManager) async throws -> Void)?
        var parakeetLoadAfterInstalledCheck: (@Sendable () async throws -> any ParakeetASRSession)?
    }

    internal static var forceCacheStoreWriteBufferFailure: Bool {
        get { return Self.testState[\.forceCacheStoreWriteBufferFailure] }
        set { Self.testState[\.forceCacheStoreWriteBufferFailure] = newValue }
    }
    internal static var forceCacheStoreWriteError: Error? {
        get { return Self.testState[\.forceCacheStoreWriteError] }
        set { Self.testState[\.forceCacheStoreWriteError] = newValue }
    }
    internal static var forceCacheStoreMidWriteFailure: Bool {
        get { return Self.testState[\.forceCacheStoreMidWriteFailure] }
        set { Self.testState[\.forceCacheStoreMidWriteFailure] = newValue }
    }
    internal static var forceCacheStoreAtomicReplaceFailure: Bool {
        get { return Self.testState[\.forceCacheStoreAtomicReplaceFailure] }
        set { Self.testState[\.forceCacheStoreAtomicReplaceFailure] = newValue }
    }
    internal static var forceCacheStoreOpenFailure: Bool {
        get { return Self.testState[\.forceCacheStoreOpenFailure] }
        set { Self.testState[\.forceCacheStoreOpenFailure] = newValue }
    }
    internal static var forceCacheKeyAttributeParseFailure: Bool {
        get { return Self.testState[\.forceCacheKeyAttributeParseFailure] }
        set { Self.testState[\.forceCacheKeyAttributeParseFailure] = newValue }
    }
    internal static var forceCacheKeyAttributeGuardFailure: Bool {
        get { return Self.testState[\.forceCacheKeyAttributeGuardFailure] }
        set { Self.testState[\.forceCacheKeyAttributeGuardFailure] = newValue }
    }

    internal static var forceModelInstallerAtomicReplaceFailure: Bool {
        get { return Self.testState[\.forceModelInstallerAtomicReplaceFailure] }
        set { Self.testState[\.forceModelInstallerAtomicReplaceFailure] = newValue }
    }
    internal static var forceModelInstallerPreflightVolumeLookupFailure: Bool {
        get { return Self.testState[\.forceModelInstallerPreflightVolumeLookupFailure] }
        set { Self.testState[\.forceModelInstallerPreflightVolumeLookupFailure] = newValue }
    }
    internal static var forceModelInstallerPreflightVolumeUnknown: Bool {
        get { return Self.testState[\.forceModelInstallerPreflightVolumeUnknown] }
        set { Self.testState[\.forceModelInstallerPreflightVolumeUnknown] = newValue }
    }

    internal static var forceModelDownloaderFileHandleFailure: Bool {
        get { return Self.testState[\.forceModelDownloaderFileHandleFailure] }
        set { Self.testState[\.forceModelDownloaderFileHandleFailure] = newValue }
    }

    internal static var forceParakeetDirectorySizeEnumeratorFailure: Bool {
        get { return Self.testState[\.forceParakeetDirectorySizeEnumeratorFailure] }
        set { Self.testState[\.forceParakeetDirectorySizeEnumeratorFailure] = newValue }
    }
    internal static var forceParakeetDirectorySizeNilEnumerator: Bool {
        get { return Self.testState[\.forceParakeetDirectorySizeNilEnumerator] }
        set { Self.testState[\.forceParakeetDirectorySizeNilEnumerator] = newValue }
    }
    internal static var forceContentsOfDirectoryFailure: Bool {
        get { return Self.testState[\.forceContentsOfDirectoryFailure] }
        set { Self.testState[\.forceContentsOfDirectoryFailure] = newValue }
    }
    internal static var forceUnzipInvalidStderr: Bool {
        get { return Self.testState[\.forceUnzipInvalidStderr] }
        set { Self.testState[\.forceUnzipInvalidStderr] = newValue }
    }
    internal static var forceEncoderBundleEnumeratorNil: Bool {
        get { return Self.testState[\.forceEncoderBundleEnumeratorNil] }
        set { Self.testState[\.forceEncoderBundleEnumeratorNil] = newValue }
    }

    /// When set, replaces FluidAudio disk load in `ensureLoaded` before `materializeFromDisk`.
    internal static var parakeetMaterializeSession: (@Sendable (URL, AsrModelVersion) async throws -> any ParakeetASRSession)? {
        get { return Self.testState[\.parakeetMaterializeSession] }
        set { Self.testState[\.parakeetMaterializeSession] = newValue }
    }

    /// When set, replaces the body of `materializeFromDisk` after the status line (no HF downloads).
    internal static var parakeetMaterializeFromDiskStub: (@Sendable (URL, AsrModelVersion) async throws -> any ParakeetASRSession)? {
        get { return Self.testState[\.parakeetMaterializeFromDiskStub] }
        set { Self.testState[\.parakeetMaterializeFromDiskStub] = newValue }
    }

    /// When set, replaces `AsrModels.load` inside `materializeFromDiskUsingFluidAudio`.
    internal static var parakeetAsrModelsLoad: (@Sendable (URL, AsrModelVersion) async throws -> AsrModels)? {
        get { return Self.testState[\.parakeetAsrModelsLoad] }
        set { Self.testState[\.parakeetAsrModelsLoad] = newValue }
    }

    /// When set, replaces `AsrManager.loadModels` inside `loadParakeetModelsIntoManager`.
    internal static var parakeetAsrManagerLoadModels: (@Sendable (AsrManager) async throws -> Void)? {
        get { return Self.testState[\.parakeetAsrManagerLoadModels] }
        set { Self.testState[\.parakeetAsrManagerLoadModels] = newValue }
    }

    /// Runs after `requireInstalled` succeeds, skipping FluidAudio load.
    internal static var parakeetLoadAfterInstalledCheck: (@Sendable () async throws -> any ParakeetASRSession)? {
        get { return Self.testState[\.parakeetLoadAfterInstalledCheck] }
        set { Self.testState[\.parakeetLoadAfterInstalledCheck] = newValue }
    }

    internal static var loadWaiterWillRegister: (@Sendable () -> Void)? {
        get { return Self.testState[\.loadWaiterWillRegister] }
        set { Self.testState[\.loadWaiterWillRegister] = newValue }
    }

    internal static var audioReadFailureAfterFrames: Int64? {
        get { return Self.testState[\.audioReadFailureAfterFrames] }
        set { Self.testState[\.audioReadFailureAfterFrames] = newValue }
    }

    internal static var audioConverterErrorWithoutDetails: Bool {
        get { return Self.testState[\.audioConverterErrorWithoutDetails] }
        set { Self.testState[\.audioConverterErrorWithoutDetails] = newValue }
    }

    /// Clears all hook flags (used by the test harness between tests).
    static func resetAll() -> Void {
        Self.audioReadFailureAfterFrames = nil
        Self.audioConverterErrorWithoutDetails = false
        Self.loadWaiterWillRegister = nil
        Self.forceCacheStoreWriteBufferFailure = false
        Self.forceCacheStoreWriteError = nil
        Self.forceCacheStoreMidWriteFailure = false
        Self.forceCacheStoreAtomicReplaceFailure = false
        Self.forceCacheStoreOpenFailure = false
        Self.forceCacheKeyAttributeParseFailure = false
        Self.forceCacheKeyAttributeGuardFailure = false
        Self.forceModelInstallerAtomicReplaceFailure = false
        Self.forceModelInstallerPreflightVolumeLookupFailure = false
        Self.forceModelInstallerPreflightVolumeUnknown = false
        Self.forceModelDownloaderFileHandleFailure = false
        Self.forceParakeetDirectorySizeEnumeratorFailure = false
        Self.forceParakeetDirectorySizeNilEnumerator = false
        Self.forceContentsOfDirectoryFailure = false
        Self.forceUnzipInvalidStderr = false
        Self.forceEncoderBundleEnumeratorNil = false
        Self.parakeetMaterializeSession = nil
        Self.parakeetMaterializeFromDiskStub = nil
        Self.parakeetAsrModelsLoad = nil
        Self.parakeetAsrManagerLoadModels = nil
        Self.parakeetLoadAfterInstalledCheck = nil
    }
}
