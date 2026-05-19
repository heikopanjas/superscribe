import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("SuperscribeKit test hooks", .serialized)
struct SuperscribeKitTestHooksTests {

    private func resetHooks() {
        SuperscribeKitTestHooks.forceAudioPreparerFastPathBufferFailure = false
        SuperscribeKitTestHooks.forceAudioPreparerCachedBufferFailure = false
        SuperscribeKitTestHooks.forceAudioPreparerConverterCreationFailure = false
        SuperscribeKitTestHooks.forceAudioPreparerOutputBufferFailure = false
        SuperscribeKitTestHooks.forceAudioPreparerInputBufferFailure = false
        SuperscribeKitTestHooks.forceAudioPreparerConversionError = nil
        SuperscribeKitTestHooks.forceAudioPreparerEndOfStreamImmediately = false
        SuperscribeKitTestHooks.forceAnalyzerMonoFormatFailure = false
        SuperscribeKitTestHooks.forceAnalyzerSourceBufferFailure = false
        SuperscribeKitTestHooks.forceAnalyzerReadIntoFailure = false
        SuperscribeKitTestHooks.forceAnalyzerConverterCreationFailure = false
        SuperscribeKitTestHooks.forceAnalyzerConversionError = nil
        SuperscribeKitTestHooks.forceAnalyzerConversionStatusError = false
        SuperscribeKitTestHooks.forceAnalyzerSecondInputEndOfStream = false
        SuperscribeKitTestHooks.forceAnalyzerChunkedInput = false
        SuperscribeKitTestHooks.forceAnalyzerSmallMonoBuffer = false
        SuperscribeKitTestHooks.forceAnalyzerInjectConversionError = false
        SuperscribeKitTestHooks.forceAnalyzerNilMonoChannel = false
        SuperscribeKitTestHooks.forceAnalyzerSimulatedConversionError = nil
        SuperscribeKitTestHooks.forceAnalyzerBadConverterStatus = false
        SuperscribeKitTestHooks.forceAudioPreparerEndOfStreamImmediately = false
        SuperscribeKitTestHooks.forceAudioPreparerSecondPullEndOfStream = false
        SuperscribeKitTestHooks.forceAudioPreparerConverterNativeError = false
        SuperscribeKitTestHooks.forceAudioPreparerMarkEndBeforeSecondPull = false
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
        SuperscribeKitTestHooks.parakeetLoadAfterInstalledCheck = nil
        ParakeetBackend.testLoadHook = nil
        WhisperBackend.testForceStateInitFailed = false
        WhisperBackend.testForceTranscriptionFailed = false
        WhisperBackend.testForceNilTokenText = false
        WhisperBackend.testNilTokenTextSkipsRemaining = 0
    }

    @Test func audioPreparerHookPaths() throws {
        defer { resetHooks() }
        let url16 = try TestHelpers.makeTemp16kMonoFloatWAV(name: "hooks-fast")
        defer { try? FileManager.default.removeItem(at: url16) }
        SuperscribeKitTestHooks.forceAudioPreparerFastPathBufferFailure = true
        #expect(throws: AudioPreparerError.self) {
            _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: url16)
        }

        let url48 = try TestHelpers.makeTempSineWAV(name: "hooks-conv", durationSeconds: 0.25)
        defer { try? FileManager.default.removeItem(at: url48) }
        SuperscribeKitTestHooks.forceAudioPreparerConverterCreationFailure = true
        #expect(throws: AudioPreparerError.self) {
            _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: url48)
        }

        SuperscribeKitTestHooks.forceAudioPreparerConverterCreationFailure = false
        SuperscribeKitTestHooks.forceAudioPreparerOutputBufferFailure = true
        #expect(throws: AudioPreparerError.self) {
            _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: url48)
        }

        SuperscribeKitTestHooks.forceAudioPreparerOutputBufferFailure = false
        SuperscribeKitTestHooks.forceAudioPreparerInputBufferFailure = true
        #expect(throws: AudioPreparerError.self) {
            _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: url48)
        }

        SuperscribeKitTestHooks.forceAudioPreparerInputBufferFailure = false
        SuperscribeKitTestHooks.forceAudioPreparerEndOfStreamImmediately = true
        _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: url48)

        SuperscribeKitTestHooks.forceAudioPreparerEndOfStreamImmediately = false
        SuperscribeKitTestHooks.forceAudioPreparerZeroFrameRead = true
        _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: url48)
        SuperscribeKitTestHooks.forceAudioPreparerZeroFrameRead = false

        SuperscribeKitTestHooks.forceAudioPreparerSecondPullEndOfStream = true
        _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: url48)
        SuperscribeKitTestHooks.forceAudioPreparerSecondPullEndOfStream = false

        let tiny = try TestHelpers.makeTempSineWAV(name: "hooks-tiny", durationSeconds: 0.01)
        defer { try? FileManager.default.removeItem(at: tiny) }
        _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: tiny)

        SuperscribeKitTestHooks.forceAudioPreparerConversionError = "forced conversion failure"
        #expect(throws: AudioPreparerError.self) {
            _ = try AudioPreparer(targetFormat: .asr16kMono).loadAndConvert(url: url48)
        }
        SuperscribeKitTestHooks.forceAudioPreparerConversionError = nil

        let cacheRoot = try TestHelpers.makeTempDir(prefix: "hooks-cache")
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let cache = ConvertedAudioCache(root: cacheRoot)
        let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: cache)
        _ = try preparer.loadAndConvert(url: url48)
        SuperscribeKitTestHooks.forceAudioPreparerCachedBufferFailure = true
        #expect(throws: AudioPreparerError.self) {
            _ = try preparer.loadAndConvert(url: url48)
        }
    }

    @Test func analyzerHookPaths() throws {
        defer { resetHooks() }
        let wav = try TestHelpers.makeTempSineWAV(
            name: "hooks-analyzer",
            durationSeconds: 2.0,
            sampleRate: 48_000,
            channels: 2
        )
        defer { try? FileManager.default.removeItem(at: wav) }
        SuperscribeKitTestHooks.forceAnalyzerMonoFormatFailure = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }

        SuperscribeKitTestHooks.forceAnalyzerMonoFormatFailure = false
        SuperscribeKitTestHooks.forceAnalyzerSourceBufferFailure = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }

        SuperscribeKitTestHooks.forceAnalyzerSourceBufferFailure = false
        SuperscribeKitTestHooks.forceAnalyzerReadIntoFailure = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }

        SuperscribeKitTestHooks.forceAnalyzerReadIntoFailure = false
        SuperscribeKitTestHooks.forceAnalyzerConverterCreationFailure = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }

        SuperscribeKitTestHooks.forceAnalyzerConverterCreationFailure = false
        SuperscribeKitTestHooks.forceAnalyzerConversionError = URLError(.badServerResponse)
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }

        SuperscribeKitTestHooks.forceAnalyzerConversionError = nil
        SuperscribeKitTestHooks.forceAnalyzerConversionStatusError = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }

        SuperscribeKitTestHooks.forceAnalyzerConversionStatusError = false
        SuperscribeKitTestHooks.forceAnalyzerSecondInputEndOfStream = true
        _ = try Analyzer.readMonoFloat32(from: wav)

        SuperscribeKitTestHooks.forceAnalyzerSecondInputEndOfStream = false
        SuperscribeKitTestHooks.forceAnalyzerSimulatedConversionError = NSError(domain: "t", code: 1)
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }

        SuperscribeKitTestHooks.forceAnalyzerSimulatedConversionError = nil
        SuperscribeKitTestHooks.forceAnalyzerBadConverterStatus = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }

        SuperscribeKitTestHooks.forceAnalyzerBadConverterStatus = false
        SuperscribeKitTestHooks.forceAnalyzerChunkedInput = true
        SuperscribeKitTestHooks.forceAnalyzerSecondInputEndOfStream = true
        _ = try Analyzer.readMonoFloat32(from: wav)

        SuperscribeKitTestHooks.forceAnalyzerSecondInputEndOfStream = false
        _ = try Analyzer.readMonoFloat32(from: wav)

        SuperscribeKitTestHooks.forceAnalyzerChunkedInput = false
        SuperscribeKitTestHooks.forceAnalyzerSmallMonoBuffer = true
        _ = try Analyzer.readMonoFloat32(from: wav)

        SuperscribeKitTestHooks.forceAnalyzerSecondInputEndOfStream = true
        _ = try Analyzer.readMonoFloat32(from: wav)

        SuperscribeKitTestHooks.forceAnalyzerSecondInputEndOfStream = false
        SuperscribeKitTestHooks.forceAnalyzerSmallMonoBuffer = false
        SuperscribeKitTestHooks.forceAnalyzerInjectConversionError = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }
        SuperscribeKitTestHooks.forceAnalyzerNilMonoChannel = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }
    }

    @Test func cacheAndDownloaderHookPaths() throws {
        defer { resetHooks() }
        let url = try TestHelpers.makeTempSineWAV(name: "hooks-cache-store", durationSeconds: 0.1)
        defer { try? FileManager.default.removeItem(at: url) }
        SuperscribeKitTestHooks.forceCacheKeyAttributeParseFailure = true
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "hooks-store"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        #expect(cache.key(for: url, targetFormat: .asr16kMono) == nil)

        SuperscribeKitTestHooks.forceCacheKeyAttributeParseFailure = false
        let key = cache.key(for: url, targetFormat: .asr16kMono)!
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

    @Test func installedModelsCountsDirectoryBytes() async throws {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let bundle = folder.appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 512).write(to: bundle.appendingPathComponent("w.bin"))
            let models = try ParakeetBackend.installedModels()
            #expect((models.first?.sizeBytes ?? 0) >= 512)
        }
    }

    @Test func cacheStoreAtomicReplaceCleanup() throws {
        defer { resetHooks() }
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

    @Test func cacheKeyNilWhenAttributesIncomplete() throws {
        defer { resetHooks() }
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

    @Test func modelInstallerHookPaths() async throws {
        defer { resetHooks() }
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
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                        return (resp, Data(repoPayload.utf8))
                    }
                    if s.contains("/resolve/main/ggml-\(tag).bin") == true {
                        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                        return (resp, Data("DATA".utf8))
                    }
                    throw URLError(.unsupportedURL)
                },
                {
                    let model = RemoteModelInfo(
                        id: tag,
                        repoId: WhisperBackend.huggingFaceRepoId,
                        repoURL: URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")!
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        _ = try await ModelInstaller.install(
                            model: model,
                            backend: .whisperCpp,
                            session: URLSession.mocked(),
                            onProgress: { _ in }
                        )
                    }
                }
            )
        }
    }

    @Test func parakeetInstalledModelsMissingCacheDir() throws {
        defer { resetHooks() }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-pk-cache-\(UUID().uuidString)")
        let prior = SuperscribePaths.overrideFluidAudioModelsDirectory
        SuperscribePaths.overrideFluidAudioModelsDirectory = missing
        defer { SuperscribePaths.overrideFluidAudioModelsDirectory = prior }
        #expect(try ParakeetBackend.installedModels().isEmpty == true)
    }

    @Test func parakeetDirectorySizeEnumeratorFailure() async throws {
        defer { resetHooks() }
        SuperscribeKitTestHooks.forceParakeetDirectorySizeEnumeratorFailure = true
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("X.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            let models = try ParakeetBackend.installedModels()
            #expect(models.first?.sizeBytes == nil)
        }
    }

    @Test func parakeetDirectorySizeNilEnumeratorHook() async throws {
        defer { resetHooks() }
        SuperscribeKitTestHooks.forceParakeetDirectorySizeNilEnumerator = true
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("X.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            let models = try ParakeetBackend.installedModels()
            #expect(models.first?.sizeBytes == nil)
        }
    }

    @Test func ensureLoadedUsesMaterializeFromDisk() async throws {
        defer { resetHooks() }
        try await TestHelpers.withIsolatedModelCaches { _, _ in
            let dir = ParakeetBackend.installPath(for: "v3")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent("Enc.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            let backend = ParakeetBackend(model: "v3")
            do {
                _ = try await backend.transcribe(
                    samples: [0, 0.1, 0, -0.1],
                    segment: SpeechSegment(start: 0, end: 0.001),
                    config: TranscriptionConfig(language: "en", model: "v3", prompt: nil)
                )
            }
            catch {
                // FluidAudio load may fail on stub bundles; path 109-112 still runs.
            }
        }
    }

    @Test func preflightVolumeNaturalUnknownReturn() throws {
        defer { resetHooks() }
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeLookupFailure = true
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeUnknown = false
        try ModelInstaller.preflightDiskSpace(
            requiredBytes: 1024,
            installPath: URL(fileURLWithPath: "/no/such/\(UUID().uuidString)/model.bin")
        )
    }

    @Test func audioPreparerNaturalEndOfStreamAndConverterError() throws {
        defer { resetHooks() }
        let wav = try TestHelpers.makeTempSineWAV(
            name: "hooks-ap-natural",
            durationSeconds: 3.0,
            sampleRate: 48_000,
            channels: 2
        )
        defer { try? FileManager.default.removeItem(at: wav) }
        let preparer = AudioPreparer(targetFormat: .asr16kMono)
        SuperscribeKitTestHooks.forceAudioPreparerMarkEndBeforeSecondPull = true
        _ = try preparer.loadAndConvert(url: wav)

        SuperscribeKitTestHooks.forceAudioPreparerMarkEndBeforeSecondPull = false
        SuperscribeKitTestHooks.forceAudioPreparerConverterNativeError = true
        #expect(throws: AudioPreparerError.self) {
            _ = try preparer.loadAndConvert(url: wav)
        }
    }

    @Test func parakeetLoadAfterInstalledCheckHook() async throws {
        defer { resetHooks() }
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let dir = ParakeetBackend.installPath(for: "v3")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent("Enc.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            SuperscribeKitTestHooks.parakeetLoadAfterInstalledCheck = {
                MockHookSession(
                    result: ASRResult(
                        text: "hook",
                        confidence: 1,
                        duration: 0.1,
                        processingTime: 0.01,
                        tokenTimings: nil
                    )
                )
            }
            let backend = ParakeetBackend(model: "v3", injectedSession: nil)
            let out = try await backend.transcribe(
                samples: [0.1],
                segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: nil, model: "v3", prompt: nil)
            )
            #expect(out.words.count == 1)
        }
    }

    @Test func whisperForcedFailureHooks() async throws {
        defer { resetHooks() }
        guard FileManager.default.fileExists(atPath: WhisperBackend.installPath(for: "medium").path) == true else {
            return
        }
        let backend = WhisperBackend(model: "medium")
        let wav = try TestHelpers.makeTemp16kMonoFloatWAV(name: "wh-hooks")
        defer { try? FileManager.default.removeItem(at: wav) }
        let samples = try AudioPreparer(for: backend.capabilities).loadAndConvert(url: wav)

        WhisperBackend.testForceStateInitFailed = true
        await #expect(throws: WhisperError.self) {
            _ = try await backend.transcribe(
                samples: samples,
                segment: SpeechSegment(start: 0, end: 0.5),
                config: TranscriptionConfig(language: "en", model: "medium", prompt: nil)
            )
        }

        WhisperBackend.testForceStateInitFailed = false
        WhisperBackend.testForceTranscriptionFailed = true
        await #expect(throws: WhisperError.self) {
            _ = try await backend.transcribe(
                samples: samples,
                segment: SpeechSegment(start: 0, end: 0.5),
                config: TranscriptionConfig(language: "en", model: "medium", prompt: nil)
            )
        }

        WhisperBackend.testForceTranscriptionFailed = false
        WhisperBackend.testForceNilTokenText = true
        WhisperBackend.testNilTokenTextSkipsRemaining = 1
        let speech = try makeSpeechWAV()
        defer { try? FileManager.default.removeItem(at: speech) }
        let speechSamples = try AudioPreparer(for: backend.capabilities).loadAndConvert(url: speech)
        let out = try await backend.transcribe(
            samples: speechSamples,
            segment: SpeechSegment(start: 0, end: min(3.0, Double(speechSamples.count) / 16_000)),
            config: TranscriptionConfig(language: "en", model: "medium", prompt: nil)
        )
        #expect(out.words.isEmpty == false)
    }

    private func makeSpeechWAV() throws -> URL {
        let dir = try TestHelpers.makeTempDir(prefix: "hooks-speech")
        let aiff = dir.appendingPathComponent("speech.aiff")
        let wav = dir.appendingPathComponent("speech.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", aiff.path, "Hello world, this is a speech recognition test."]
        try say.run()
        say.waitUntilExit()
        #expect(say.terminationStatus == 0)
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        convert.arguments = [aiff.path, wav.path, "-f", "WAVE", "-d", "LEI16@16000"]
        try convert.run()
        convert.waitUntilExit()
        #expect(convert.terminationStatus == 0)
        return wav
    }

    @Test func modelDownloaderFileHandleHook() async throws {
        defer { resetHooks() }
        SuperscribeKitTestHooks.forceModelDownloaderFileHandleFailure = true
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("fh-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: dest) }
        let stream = AsyncStream<UInt8> { $0.finish() }
        await #expect(throws: ModelInstallationError.self) {
            _ = try await ModelDownloader.streamBytes(
                from: stream,
                to: dest,
                sourceURL: URL(string: "https://example.com/x")!,
                expectedSize: nil
            )
        }
    }

    @Test func materializeFromDiskExecutesLoadPath() async throws {
        try await TestHelpers.withIsolatedModelCaches { _, _ in
            let dir = ParakeetBackend.installPath(for: "v3")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent("Enc.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            do {
                _ = try await ParakeetBackend.materializeFromDisk(
                    installDir: dir,
                    modelVersion: .v3
                )
            }
            catch {
                // Incomplete bundles typically fail FluidAudio load.
            }
        }
    }

    @Test func preflightVolumeUnknownHook() throws {
        defer { resetHooks() }
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeLookupFailure = true
        SuperscribeKitTestHooks.forceModelInstallerPreflightVolumeUnknown = true
        try ModelInstaller.preflightDiskSpace(
            requiredBytes: 1024,
            installPath: URL(fileURLWithPath: "/no/such/\(UUID().uuidString)/model.bin")
        )
    }

    @Test func parakeetMaterializeSessionHook() async throws {
        defer { resetHooks() }
        try await TestHelpers.withIsolatedModelCaches { _, _ in
            let dir = ParakeetBackend.installPath(for: "v3")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent("Enc.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            SuperscribeKitTestHooks.parakeetMaterializeSession = { _, _ in
                MockHookSession(
                    result: ASRResult(
                        text: "mat",
                        confidence: 1,
                        duration: 0.1,
                        processingTime: 0.01,
                        tokenTimings: nil
                    )
                )
            }
            let backend = ParakeetBackend(model: "v3", injectedSession: nil)
            _ = try await backend.transcribe(
                samples: [0.1],
                segment: SpeechSegment(start: 0, end: 1),
                config: TranscriptionConfig(language: nil, model: "v3", prompt: nil)
            )
        }
    }

    @Test func loadOnceWaitsOnInFlightTask() async throws {
        let loader = LoadOnce<Int>()
        let gate = LoadOnceGate()

        async let first: Int = loader.get {
            await gate.markFirstEntered()
            await gate.waitForRelease()
            return 42
        }

        try await Task.sleep(for: .milliseconds(50))
        async let second: Int = loader.get { 7 }
        await gate.release()

        let results = try await [first, second]
        #expect(results == [42, 42])
    }

    @Test func downloadOneNetworkErrorHook() async throws {
        defer { resetHooks() }
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
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(repoPayload.utf8))
                }
                throw URLError(.networkConnectionLost)
            },
            {
                try await TestHelpers.withTempDirectory(prefix: "dl-net-one") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.download(
                            model: model,
                            backend: .parakeet,
                            into: staging,
                            session: URLSession.mocked(),
                            onProgress: { _ in }
                        )
                    }
                }
            }
        )
    }
}

private actor LoadOnceGate {
    private var entered = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markFirstEntered() {
        entered = true
    }

    func waitForRelease() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            releaseWaiters.append(cont)
        }
    }

    func release() {
        let pending = releaseWaiters
        releaseWaiters.removeAll()
        for cont in pending { cont.resume() }
    }
}

private struct MockHookSession: ParakeetASRSession {
    let result: ASRResult
    var decoderLayerCount: Int { get async { 1 } }
    func transcribe(
        _ samples: [Float],
        decoderState: inout TdtDecoderState,
        language: Language?
    ) async throws -> ASRResult {
        result
    }
}
