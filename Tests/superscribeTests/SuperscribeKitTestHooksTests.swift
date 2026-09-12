import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("SuperscribeKit test hooks", .serialized, ResetSharedStateTrait())
struct SuperscribeKitTestHooksTests {

    private func resetHooks() -> Void {
        SuperscribeKitTestHooks.forceCacheStoreMidWriteFailure = false
        SuperscribeKitTestHooks.forceCacheStoreAtomicReplaceFailure = false
        SuperscribeKitTestHooks.forceCacheStoreOpenFailure = false
        SuperscribeKitTestHooks.forceCacheStoreWriteBufferFailure = false
        SuperscribeKitTestHooks.forceCacheStoreWriteError = nil
        SuperscribeKitTestHooks.forceCacheStoreAtomicReplaceFailure = false
        SuperscribeKitTestHooks.forceCacheStoreOpenFailure = false
        SuperscribeKitTestHooks.forceCacheKeyAttributeParseFailure = false
        SuperscribeKitTestHooks.forceCacheKeyAttributeGuardFailure = false
        SuperscribeKitTestHooks.forceModelInstallerAtomicReplaceFailure = false
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeLookupFailure = false
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeUnknown = false
        SuperscribeKitTestHooks.forceModelDownloaderFileHandleFailure = false
        SuperscribeKitTestHooks.forceParakeetDirectorySizeEnumeratorFailure = false
        SuperscribeKitTestHooks.forceParakeetDirectorySizeNilEnumerator = false
        SuperscribeKitTestHooks.parakeetMaterializeSession = nil
        SuperscribeKitTestHooks.parakeetMaterializeFromDiskStub = nil
        SuperscribeKitTestHooks.parakeetAsrModelsLoad = nil
        SuperscribeKitTestHooks.parakeetAsrManagerLoadModels = nil
        SuperscribeKitTestHooks.parakeetLoadAfterInstalledCheck = nil
        ParakeetBackend.testLoadHook = nil
        WhisperBackend.testForceStateInitFailed = false
        WhisperBackend.testForceTranscriptionFailed = false
        WhisperBackend.testForceNilTokenText = false
        WhisperBackend.testNilTokenTextSkipsRemaining = 0
        WhisperBackend.testUseStubLoad = false
        WhisperBackend.testWhisperAPISegments = nil
        WhisperBackend.testWhisperInitPointer = nil
        WhisperBackend.testWhisperStatePointer = nil
        WhisperLiveAPI.testSkipContextRelease = false
    }

    @Test func cacheAndDownloaderHookPaths() throws -> Void {
        defer { self.resetHooks() }
        let url = try TestHelpers.makeTempSineWAV(name: "hooks-cache-store", durationSeconds: 0.1)
        defer { try? FileManager.default.removeItem(at: url) }
        SuperscribeKitTestHooks.forceCacheKeyAttributeParseFailure = true
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "hooks-store"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        #expect(cache.key(for: url, targetFormat: .asr16kMono) == nil)

        SuperscribeKitTestHooks.forceCacheKeyAttributeParseFailure = false
        let key = (try #require(cache.key(for: url, targetFormat: .asr16kMono)))
        SuperscribeKitTestHooks.forceCacheStoreWriteBufferFailure = true
        #expect(throws: AudioPreparerError.self) {
            _ = try cache.store(samples: [0.1], format: .asr16kMono, key: key)
        }

        SuperscribeKitTestHooks.forceCacheStoreWriteBufferFailure = false
        SuperscribeKitTestHooks.forceCacheStoreWriteError = CocoaError(.fileWriteUnknown)
        SuperscribeKitTestHooks.forceCacheStoreMidWriteFailure = true
        #expect(throws: Error.self) {
            _ = try cache.store(samples: [0.1, 0.2], format: .asr16kMono, key: key)
        }

        SuperscribeKitTestHooks.forceCacheStoreWriteError = nil
        SuperscribeKitTestHooks.forceCacheStoreMidWriteFailure = true
        #expect(throws: Error.self) {
            _ = try cache.store(samples: [0.1, 0.2, 0.3], format: .asr16kMono, key: key)
        }

        SuperscribeKitTestHooks.forceCacheStoreMidWriteFailure = false
    }

    @Test func installedModelsCountsDirectoryBytes() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try TestHelpers.makeParakeetInstallation(at: folder)
            let bundle = folder.appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 512).write(to: bundle.appendingPathComponent("w.bin"))
            let models = try ParakeetBackend.installedModels()
            #expect((models.first?.sizeBytes ?? 0) >= 512)
        }
    }

    @Test func cacheStoreAtomicReplaceCleanup() throws -> Void {
        defer { self.resetHooks() }
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "hooks-atomic"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let key = ConvertedAudioCache.CacheKey(
            sourcePath: "/tmp/a.wav",
            sourceSize: 1,
            sourceMtimeNanos: 1,
            formatKey: "f32-16000-1"
        )
        SuperscribeKitTestHooks.forceCacheStoreAtomicReplaceFailure = true
        #expect(throws: Error.self) {
            _ = try cache.store(samples: [0.1], format: .asr16kMono, key: key)
        }
    }

    @Test func cacheKeyNilWhenAttributesIncomplete() throws -> Void {
        defer { self.resetHooks() }
        let url = try TestHelpers.makeTempSineWAV(name: "key-partial", durationSeconds: 0.05)
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "key-nil"))
        defer { try? FileManager.default.removeItem(at: cache.root) }

        SuperscribeKitTestHooks.forceCacheKeyAttributeGuardFailure = true
        #expect(cache.key(for: url, targetFormat: .asr16kMono) == nil)

        SuperscribeKitTestHooks.forceCacheKeyAttributeGuardFailure = false
        SuperscribeKitTestHooks.forceCacheKeyAttributeParseFailure = true
        #expect(cache.key(for: url, targetFormat: .asr16kMono) == nil)
    }

    @Test func modelInstallerHookPaths() async throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeUnknown = true
        try ModelInstaller.preflightDiskSpace(requiredBytes: 1024, installPath: URL(fileURLWithPath: "/no/such/model.bin"))

        try await TestHelpers.withIsolatedModelCaches { _, whisperRoot in
            let tag = "wt-hook-\(UUID().uuidString.prefix(8))"
            let repoPayload = """
                {"id":"\(WhisperBackend.huggingFaceRepoId)","lastModified":null,"siblings":[
                  {"rfilename":"ggml-\(tag).bin","size":4}
                ]}
                """
            SuperscribeKitTestHooks.forceModelInstallerAtomicReplaceFailure = true
            try await MockURLSessionHelpers.withMockHandler(
                { req in
                    guard let url = req.url else { throw URLError(.badURL) }
                    let s = url.absoluteString
                    if s.contains("/api/models/") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data(repoPayload.utf8))
                    }
                    if s.contains("/resolve/main/ggml-\(tag).bin") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data("DATA".utf8))
                    }
                    throw URLError(.unsupportedURL)
                },
                { session in
                    let model = RemoteModelInfo(
                        id: tag,
                        repoId: WhisperBackend.huggingFaceRepoId,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")))
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        _ = try await ModelInstaller.install(
                            model: model,
                            backend: .whisperCpp,
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            )
        }
    }

    @Test func parakeetInstalledModelsMissingCacheDir() throws -> Void {
        defer { self.resetHooks() }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-pk-cache-\(UUID().uuidString)")
        let prior = SuperscribePaths.overrideFluidAudioModelsDirectory
        SuperscribePaths.overrideFluidAudioModelsDirectory = missing
        defer { SuperscribePaths.overrideFluidAudioModelsDirectory = prior }
        #expect(try ParakeetBackend.installedModels().isEmpty == true)
    }

    @Test func parakeetDirectorySizeEnumeratorFailure() async throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.forceParakeetDirectorySizeEnumeratorFailure = true
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try TestHelpers.makeParakeetInstallation(at: folder)
            let models = try ParakeetBackend.installedModels()
            #expect(models.first?.sizeBytes == nil)
        }
    }

    @Test func parakeetDirectorySizeNilEnumeratorHook() async throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.forceParakeetDirectorySizeNilEnumerator = true
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try TestHelpers.makeParakeetInstallation(at: folder)
            let models = try ParakeetBackend.installedModels()
            #expect(models.first?.sizeBytes == nil)
        }
    }

    @Test func ensureLoadedCallsMaterializeFromDiskStub() async throws -> Void {
        defer { self.resetHooks() }
        try await TestHelpers.withIsolatedModelCaches { _, _ in
            let dir = try ParakeetBackend.installPath(for: "v3")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try TestHelpers.makeParakeetInstallation(at: dir)
            SuperscribeKitTestHooks.parakeetMaterializeFromDiskStub = { installDir, version in
                #expect(installDir.path == dir.path)
                #expect(version == .v3)
                return MockParakeetSession(
                    result: ASRResult(
                        text: "stub",
                        confidence: 1,
                        duration: 0.1,
                        processingTime: 0.01,
                        tokenTimings: nil
                    )
                )
            }
            let backend = try ParakeetBackend(model: "v3", injectedSession: nil)
            let out = try await backend.transcribe(
                samples: [0.1],
                segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: nil, prompt: nil)
            )
            #expect(out.words.count == 1)
            #expect(out.words[0].text == "stub")
        }
    }

    @Test func preflightVolumeNaturalUnknownReturn() throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeLookupFailure = true
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeUnknown = false
        try ModelInstaller.preflightDiskSpace(
            requiredBytes: 1024,
            installPath: URL(fileURLWithPath: "/no/such/\(UUID().uuidString)/model.bin")
        )
    }

    @Test func parakeetLoadAfterInstalledCheckHook() async throws -> Void {
        defer { self.resetHooks() }
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let dir = try ParakeetBackend.installPath(for: "v3")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try TestHelpers.makeParakeetInstallation(at: dir)
            SuperscribeKitTestHooks.parakeetLoadAfterInstalledCheck = {
                MockParakeetSession(
                    result: ASRResult(
                        text: "hook",
                        confidence: 1,
                        duration: 0.1,
                        processingTime: 0.01,
                        tokenTimings: nil
                    )
                )
            }
            let backend = try ParakeetBackend(model: "v3", injectedSession: nil)
            let out = try await backend.transcribe(
                samples: [0.1],
                segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: nil, prompt: nil)
            )
            #expect(out.words.count == 1)
        }
    }

    @Test func whisperForcedFailureHooks() async throws -> Void {
        defer { self.resetHooks() }
        WhisperBackend.testUseStubLoad = true
        let backend = try WhisperBackend(model: "stub-hooks")
        let samples = [Float](repeating: 0, count: 16_000)

        WhisperBackend.testForceStateInitFailed = true
        await #expect(throws: WhisperError.self) {
            _ = try await backend.transcribe(
                samples: samples,
                segment: SpeechSegment(start: 0, end: 0.5),
                config: TranscriptionConfig(language: "en", prompt: nil)
            )
        }

        WhisperBackend.testForceStateInitFailed = false
        WhisperBackend.testWhisperAPISegments = [
            [
                WhisperTestToken(token: " x", id: 1, t0: 0, t1: 10)
            ]
        ]
        WhisperBackend.testForceTranscriptionFailed = true
        await #expect(throws: WhisperError.self) {
            _ = try await backend.transcribe(
                samples: samples,
                segment: SpeechSegment(start: 0, end: 0.5),
                config: TranscriptionConfig(language: "en", prompt: nil)
            )
        }

        WhisperBackend.testForceTranscriptionFailed = false
        WhisperBackend.testWhisperAPISegments = [
            [
                WhisperTestToken(token: " hello", id: 1, t0: 0, t1: 50),
                WhisperTestToken(token: " world", id: 2, t0: 50, t1: 100)
            ]
        ]
        WhisperBackend.testForceNilTokenText = true
        WhisperBackend.testNilTokenTextSkipsRemaining = 1
        let out = try await backend.transcribe(
            samples: samples,
            segment: SpeechSegment(start: 0, end: 1.0),
            config: TranscriptionConfig(language: "en", prompt: nil)
        )
        #expect(out.words.isEmpty == false)
    }

    @Test func modelDownloaderFileHandleHook() async throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.forceModelDownloaderFileHandleFailure = true
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("fh-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: dest) }
        let stream = AsyncStream<UInt8> { $0.finish() }
        await #expect(throws: ModelInstallationError.self) {
            _ = try await ModelDownloader.streamBytes(
                from: stream,
                to: dest,
                sourceURL: (try #require(URL(string: "https://example.com/x"))),
                expectedSize: nil
            )
        }
    }

    @Test func loadAsrModelsFromFluidAudioRejectsCtcOnlyModel() async -> Void {
        defer { self.resetHooks() }
        await #expect(throws: Error.self) {
            _ = try await ParakeetBackend.loadAsrModelsFromFluidAudio(
                from: URL(fileURLWithPath: "/tmp/parakeet-ctc-\(UUID().uuidString)"),
                version: .ctcZhCn
            )
        }
    }

    @Test func materializeFromDiskFallsThroughToFluidAudioHooks() async throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.parakeetAsrModelsLoad = { _, _ in
            try TestHelpers.makeStubAsrModels()
        }
        SuperscribeKitTestHooks.parakeetAsrManagerLoadModels = { _ in }
        _ = try await ParakeetBackend.materializeFromDisk(
            installDir: URL(fileURLWithPath: "/tmp/parakeet-fallthrough-\(UUID().uuidString)"),
            modelVersion: .v3
        )
    }

    @Test func materializeFromDiskStubSkipsFluidAudioDownload() async throws -> Void {
        defer { self.resetHooks() }
        let installDir = URL(fileURLWithPath: "/tmp/parakeet-stub-\(UUID().uuidString)")
        SuperscribeKitTestHooks.parakeetMaterializeFromDiskStub = { dir, version in
            #expect(dir.path == installDir.path)
            #expect(version == .v3)
            return MockParakeetSession(
                result: ASRResult(
                    text: "disk-stub",
                    confidence: 1,
                    duration: 0.1,
                    processingTime: 0.01,
                    tokenTimings: nil
                )
            )
        }
        let session = try await ParakeetBackend.materializeFromDisk(
            installDir: installDir,
            modelVersion: .v3
        )
        var decoderState = TdtDecoderState.make(decoderLayers: await session.decoderLayerCount)
        let out = try await session.transcribe(
            [0.1],
            decoderState: &decoderState,
            language: nil
        )
        #expect(out.text == "disk-stub")
    }

    @Test func materializeFromDiskUsingFluidAudioManagerLoadHook() async throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.parakeetAsrModelsLoad = { _, _ in
            try TestHelpers.makeStubAsrModels()
        }
        SuperscribeKitTestHooks.parakeetAsrManagerLoadModels = { _ in }
        _ = try await ParakeetBackend.materializeFromDiskUsingFluidAudio(
            installDir: URL(fileURLWithPath: "/tmp/parakeet-mgr-\(UUID().uuidString)"),
            modelVersion: .v3
        )
    }

    @Test func materializeFromDiskUsingFluidAudioCompletesWithoutManagerHook() async throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.parakeetAsrModelsLoad = { _, _ in
            try TestHelpers.makeStubAsrModels()
        }
        _ = try await ParakeetBackend.materializeFromDiskUsingFluidAudio(
            installDir: URL(fileURLWithPath: "/tmp/parakeet-full-\(UUID().uuidString)"),
            modelVersion: .v3
        )
    }

    @Test func loadParakeetModelsIntoManagerInvokesFluidAudioLoadModels() async throws -> Void {
        defer { self.resetHooks() }
        let models = try TestHelpers.makeStubAsrModels()
        try await ParakeetBackend.loadParakeetModelsIntoManager(AsrManager(), models: models)
    }

    @Test func loadAsrModelsUsesFluidAudioFallbackForCtcOnly() async -> Void {
        defer { self.resetHooks() }
        await #expect(throws: Error.self) {
            _ = try await ParakeetBackend.materializeFromDiskUsingFluidAudio(
                installDir: URL(fileURLWithPath: "/tmp/parakeet-ctc-fallback-\(UUID().uuidString)"),
                modelVersion: .ctcZhCn
            )
        }
    }

    @Test func materializeFromDiskUsingFluidAudioLoadHookThrows() async throws -> Void {
        defer { self.resetHooks() }
        struct StubLoadError: Error {}
        SuperscribeKitTestHooks.parakeetAsrModelsLoad = { _, _ in
            throw StubLoadError()
        }
        await #expect(throws: StubLoadError.self) {
            _ = try await ParakeetBackend.materializeFromDiskUsingFluidAudio(
                installDir: URL(fileURLWithPath: "/tmp/parakeet-throw-\(UUID().uuidString)"),
                modelVersion: .v3
            )
        }
    }

    @Test func preflightVolumeUnknownHook() throws -> Void {
        defer { self.resetHooks() }
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeLookupFailure = true
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeUnknown = true
        try ModelInstaller.preflightDiskSpace(
            requiredBytes: 1024,
            installPath: URL(fileURLWithPath: "/no/such/\(UUID().uuidString)/model.bin")
        )
    }

    @Test func parakeetMaterializeSessionHook() async throws -> Void {
        defer { self.resetHooks() }
        try await TestHelpers.withIsolatedModelCaches { _, _ in
            let dir = try ParakeetBackend.installPath(for: "v3")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try TestHelpers.makeParakeetInstallation(at: dir)
            SuperscribeKitTestHooks.parakeetMaterializeSession = { _, _ in
                MockParakeetSession(
                    result: ASRResult(
                        text: "mat",
                        confidence: 1,
                        duration: 0.1,
                        processingTime: 0.01,
                        tokenTimings: nil
                    )
                )
            }
            let backend = try ParakeetBackend(model: "v3", injectedSession: nil)
            _ = try await backend.transcribe(
                samples: [0.1],
                segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: nil, prompt: nil)
            )
        }
    }

    @Test func loadOnceWaitsOnInFlightTask() async throws -> Void {
        let loader = LoadOnce<Int>()
        let gate = LoadOnceGate()

        async let first: Int = loader.get {
            await gate.markFirstEntered()
            await gate.waitForRelease()
            return 42
        }

        await gate.waitUntilFirstEntered()
        async let second: Int = loader.get { 7 }
        await gate.release()

        let results = try await [first, second]
        #expect(results == [42, 42])
    }

    @Test func downloadOneNetworkErrorHook() async throws -> Void {
        defer { self.resetHooks() }
        let repoId = "FluidInference/net-err"
        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"a.bin","size":3}
            ]}
            """
        _ = try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(repoPayload.utf8))
                }
                throw URLError(.networkConnectionLost)
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-net-one") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.download(
                            model: model,
                            backend: .parakeet,
                            into: staging,
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            }
        )
    }
}
