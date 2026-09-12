import AVFoundation
import FluidAudio
import Foundation

/// FluidAudio Parakeet TDT v3 backend for on-device speech-to-text.
///
/// Uses the Apple Neural Engine for inference, keeping the GPU free.
/// Models are downloaded automatically on first use and cached at
/// `~/.cache/fluidaudio/Models/`.
public actor ParakeetBackend: Transcriber {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var overrideRemoteModelsSession: URLSession?
        var defaultRemoteModelsSession: URLSession = .shared
        var testLoadHook: (@Sendable () async throws -> any ParakeetASRSession)?
        var testForceUnavailable = false
    }

    /// Test hook for `ensureLoaded()` disk path without FluidAudio on disk.
    internal static var testLoadHook: (@Sendable () async throws -> any ParakeetASRSession)? {
        get { return Self.testState[\.testLoadHook] }
        set { Self.testState[\.testLoadHook] = newValue }
    }
    /// When `true`, `isAvailable` reports unavailable (for dispatch tests).
    internal static var testForceUnavailable: Bool {
        get { return Self.testState[\.testForceUnavailable] }
        set { Self.testState[\.testForceUnavailable] = newValue }
    }

    public nonisolated static var isAvailable: Bool {
        if Self.testForceUnavailable == true { return false }
        return true
    }

    private let loader = LoadOnce<any ParakeetASRSession>()
    private let descriptor: ModelDescriptor
    private nonisolated var modelVersion: AsrModelVersion { return self.descriptor.version }
    private let injectedSession: (any ParakeetASRSession)?

    /// - Throws: `UnsupportedModelError` for an unknown model.
    /// - Parameter model: Model version string. Accepted values:
    ///   `"v3"` (multilingual, default), `"v2"` (English-only),
    ///   `"tdt-ctc-110m"`, `"tdt-ja"`.
    public init(model: String = "v3") throws {
        try self.init(model: model, injectedSession: nil)
    }

    /// Test-only injection point for `ParakeetASRSession` (skips disk load).
    internal init(model: String, injectedSession: (any ParakeetASRSession)?) throws {
        self.descriptor = try Self.descriptor(for: model)
        self.injectedSession = injectedSession
    }

    public nonisolated var modelId: String { return self.descriptor.id }

    public nonisolated var capabilities: BackendCapabilities {
        return BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Parakeet TDT \(self.modelVersion) (FluidAudio)",
            defaultModelId: ParakeetBackend.defaultModelId
        )
    }

    // MARK: - Transcriber

    public func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        let manager = try await self.ensureLoaded()

        // Map config.language to FluidAudio's Language enum.
        let language: Language? = config.language.flatMap { Language(rawValue: $0) }

        // Transcribe with a fresh decoder state per segment.
        var decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount
        )
        let asrResult = try await manager.transcribe(
            samples,
            decoderState: &decoderState,
            language: language
        )

        return ParakeetResultMapping.map(asrResult, segment: segment)
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> any ParakeetASRSession {
        if let injectedSession = self.injectedSession {
            return injectedSession
        }
        return try await self.loader.get { [descriptor = self.descriptor] in
            let modelVersion = descriptor.version
            if let testLoadHook = Self.testLoadHook {
                return try await testLoadHook()
            }
            let modelId = descriptor.id
            let installDir = try Self.installPath(for: modelId)
            try ModelInstallSupport.requireInstalled(
                at: installDir, modelId: modelId, backend: .parakeet
            )
            FileHandle.standardError.write(
                Data("Loading Parakeet TDT \(modelVersion) models from local cache...\n".utf8)
            )
            if let afterInstalled = SuperscribeKitTestHooks.parakeetLoadAfterInstalledCheck {
                return try await afterInstalled()
            }
            if let materialize = SuperscribeKitTestHooks.parakeetMaterializeSession {
                return try await materialize(installDir, modelVersion)
            }
            return try await Self.materializeFromDisk(
                installDir: installDir,
                modelVersion: modelVersion
            )
        }
    }

    /// Loads a validated local installation. Unit tests inject storage-only model construction.
    internal static func materializeFromDisk(
        installDir: URL,
        modelVersion: AsrModelVersion
    ) async throws -> any ParakeetASRSession {
        FileHandle.standardError.write(
            Data("Loading Parakeet TDT \(modelVersion) models from local cache...\n".utf8)
        )
        if let stub = SuperscribeKitTestHooks.parakeetMaterializeFromDiskStub {
            return try await stub(installDir, modelVersion)
        }
        return try await Self.materializeFromDiskUsingFluidAudio(
            installDir: installDir,
            modelVersion: modelVersion
        )
    }

    /// Real FluidAudio disk load; covered by integration tests or hook tests without downloads.
    internal static func materializeFromDiskUsingFluidAudio(
        installDir: URL,
        modelVersion: AsrModelVersion
    ) async throws -> any ParakeetASRSession {
        let mgr = AsrManager()
        let loadedModels = try await Self.loadAsrModels(
            installDir: installDir,
            modelVersion: modelVersion
        )
        try await Self.loadParakeetModelsIntoManager(mgr, models: loadedModels)
        return mgr as any ParakeetASRSession
    }

    /// FluidAudio `AsrModels.load` wrapper (integration + fast-fail unit tests).
    internal static func loadAsrModelsFromFluidAudio(
        from installDir: URL,
        version: AsrModelVersion
    ) async throws -> AsrModels {
        return try await AsrModels.load(from: installDir, version: version)
    }

    /// FluidAudio `AsrManager.loadModels` wrapper (integration + stub unit tests).
    internal static func loadParakeetModelsIntoManager(
        _ mgr: AsrManager,
        models: AsrModels
    ) async throws -> Void {
        if let mgrLoad = SuperscribeKitTestHooks.parakeetAsrManagerLoadModels {
            try await mgrLoad(mgr)
            return
        }
        try await mgr.loadModels(models)
    }

    private static func loadAsrModels(
        installDir: URL,
        modelVersion: AsrModelVersion
    ) async throws -> AsrModels {
        if let load = SuperscribeKitTestHooks.parakeetAsrModelsLoad {
            return try await load(installDir, modelVersion)
        }
        return try await Self.loadAsrModelsFromFluidAudio(
            from: installDir,
            version: modelVersion
        )
    }

}
