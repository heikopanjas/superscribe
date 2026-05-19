import AVFoundation
import FluidAudio
import Foundation

/// FluidAudio Parakeet TDT v3 backend for on-device speech-to-text.
///
/// Uses the Apple Neural Engine for inference, keeping the GPU free.
/// Models are downloaded automatically on first use and cached at
/// `~/.cache/fluidaudio/Models/`.
public actor ParakeetBackend: Transcriber {
    /// Test hook for `ensureLoaded()` disk path without FluidAudio on disk.
    nonisolated(unsafe) internal static var testLoadHook: (@Sendable () async throws -> any ParakeetASRSession)?
    /// When `true`, `isAvailable` reports unavailable (for dispatch tests).
    nonisolated(unsafe) internal static var testForceUnavailable = false

    public nonisolated static var isAvailable: Bool {
        if testForceUnavailable == true { return false }
        return true
    }

    private let loader = LoadOnce<any ParakeetASRSession>()
    private let modelVersion: AsrModelVersion
    private let injectedSession: (any ParakeetASRSession)?

    /// - Parameter model: Model version string. Accepted values:
    ///   `"v3"` (multilingual, default), `"v2"` (English-only),
    ///   `"tdt-ctc-110m"`, `"tdt-ja"`.
    public init(model: String = "v3") {
        self.init(model: model, injectedSession: nil)
    }

    /// Test-only injection point for `ParakeetASRSession` (skips disk load).
    internal init(model: String, injectedSession: (any ParakeetASRSession)?) {
        self.modelVersion = Self.parseModelVersion(model)
        self.injectedSession = injectedSession
    }

    private static func parseModelVersion(_ model: String) -> AsrModelVersion {
        switch model.lowercased() {
            case "v2": return .v2
            case "v3": return .v3
            case "tdt-ctc-110m", "tdtctc110m", "110m": return .tdtCtc110m
            case "tdt-ja", "tdtja", "ja": return .tdtJa
            default: return .v3
        }
    }

    public nonisolated var capabilities: BackendCapabilities {
        BackendCapabilities(
            requiredAudioFormat: .asr16kMono,
            displayName: "Parakeet TDT \(modelVersion) (FluidAudio)",
            defaultModelId: ParakeetBackend.defaultModelId
        )
    }

    // MARK: - Transcriber

    public func transcribe(
        samples: [Float],
        segment: SpeechSegment,
        config: TranscriptionConfig
    ) async throws -> SegmentTranscription {
        let manager = try await ensureLoaded()

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
        if let injectedSession {
            return injectedSession
        }
        return try await loader.get { [modelVersion] in
            if let testLoadHook = Self.testLoadHook {
                return try await testLoadHook()
            }
            let modelId = ParakeetBackend.shortIdForVersion(modelVersion)
            let installDir = ParakeetBackend.installPath(for: modelId)
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

    /// Loads FluidAudio ASR models from `installDir`. Unit tests should set
    /// `SuperscribeKitTestHooks.parakeetMaterializeFromDiskStub` to avoid HF downloads.
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
        return try await materializeFromDiskUsingFluidAudio(
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
        let loadedModels = try await loadAsrModels(
            installDir: installDir,
            modelVersion: modelVersion
        )
        try await loadParakeetModelsIntoManager(mgr, models: loadedModels)
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
    ) async throws {
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
        return try await loadAsrModelsFromFluidAudio(
            from: installDir,
            version: modelVersion
        )
    }

    internal static func shortIdForVersion(_ v: AsrModelVersion) -> String {
        switch v {
            case .v2: return "v2"
            case .v3: return "v3"
            case .tdtCtc110m: return "tdt-ctc-110m"
            case .tdtJa: return "tdt-ja"
            @unknown default: return "v3"
        }
    }
}
