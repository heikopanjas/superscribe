import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - Analyzer

@Suite("Analyzer URL I/O", .serialized, ResetSharedStateTrait())
struct AnalyzerURLTests {
    @Test func errorDescriptions() {
        let url = URL(fileURLWithPath: "/tmp/missing.wav")
        #expect(AnalyzerError.unsupportedFormat(url).description.contains("Unsupported") == true)
        let read = AnalyzerError.readFailed(url, underlying: URLError(.fileDoesNotExist))
        #expect(read.description.contains("missing.wav") == true)
    }

    @Test func detectSpeechFromURL() throws {
        let wav = try TestHelpers.makeTempSineWAV(name: "analyzer-url", durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: wav) }
        let analyzer = Analyzer(config: AnalyzerConfig(padding: 0))
        let segments = try analyzer.detectSpeech(in: wav)
        #expect(segments.isEmpty == false)
    }

    @Test func detectSpeechFromStereoURL() throws {
        let wav = try TestHelpers.makeTempSineWAV(
            name: "analyzer-stereo",
            durationSeconds: 0.5,
            sampleRate: 48_000,
            channels: 2
        )
        defer { try? FileManager.default.removeItem(at: wav) }
        let segments = try Analyzer().detectSpeech(in: wav)
        #expect(segments.isEmpty == false)
    }

    @Test func readMonoFloat32MissingFileThrows() throws {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).wav")
        #expect(throws: AnalyzerError.self) {
            _ = try Analyzer.readMonoFloat32(from: url)
        }
    }

    @Test func readMonoFloat32RejectsNonAudioFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-audio-\(UUID().uuidString).txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: AnalyzerError.self) {
            _ = try Analyzer.readMonoFloat32(from: url)
        }
    }
}

// MARK: - AudioPreparer

@Suite("AudioPreparer edge cases", .serialized, ResetSharedStateTrait())
struct AudioPreparerEdgeTests {
    @Test func errorDescriptions() {
        let url = URL(fileURLWithPath: "/tmp/x.wav")
        #expect(AudioPreparerError.cannotReadFile(url, underlying: URLError(.badURL)).description.contains("Cannot read") == true)
        #expect(AudioPreparerError.unsupportedFormat(url).description.contains("Unsupported") == true)
        #expect(AudioPreparerError.conversionFailed("boom").description.contains("boom") == true)
    }

    @Test func cannotReadMissingSource() {
        let url = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).wav")
        let preparer = AudioPreparer(targetFormat: .asr16kMono)
        #expect(throws: AudioPreparerError.self) {
            _ = try preparer.loadAndConvert(url: url)
        }
    }

    @Test func fastPathWhenSourceMatchesTargetFormat() throws {
        let url = try TestHelpers.makeTemp16kMonoFloatWAV(name: "fast-path")
        defer { try? FileManager.default.removeItem(at: url) }
        let preparer = AudioPreparer(targetFormat: .asr16kMono)
        let samples = try preparer.loadAndConvert(url: url)
        #expect(samples.isEmpty == false)
    }

    @Test func cacheWriteFailureIsNonFatal() throws {
        let url = try TestHelpers.makeTempSineWAV(name: "cache-fail", durationSeconds: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let cache = ConvertedAudioCache(root: blocker)
        let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: cache)
        let samples = try preparer.loadAndConvert(url: url)
        #expect(samples.isEmpty == false)
    }

    @Test func loadCachedThrowsWhenCacheFileCorrupt() throws {
        let url = try TestHelpers.makeTempSineWAV(name: "cached-bad", durationSeconds: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        let cacheRoot = try TestHelpers.makeTempDir(prefix: "cache-root")
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let cache = ConvertedAudioCache(root: cacheRoot)
        let preparer = AudioPreparer(targetFormat: .asr16kMono, cache: cache)
        _ = try preparer.loadAndConvert(url: url)
        let key = cache.key(for: url, targetFormat: .asr16kMono)!
        let cachedURL = try #require(cache.lookup(key))
        try Data("not-a-wav".utf8).write(to: cachedURL)
        #expect(throws: AudioPreparerError.self) {
            _ = try preparer.loadAndConvert(url: url)
        }
    }
}

// MARK: - ConvertedAudioCache

@Suite("ConvertedAudioCache manifest", .serialized, ResetSharedStateTrait())
struct ConvertedAudioCacheManifestTests {
    @Test func defaultRootUsesSuperscribePaths() {
        let cache = ConvertedAudioCache()
        #expect(cache.root == SuperscribePaths.audioCacheRoot())
    }

    @Test func keyReturnsNilForMissingFile() throws {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "cache-key"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let missing = URL(fileURLWithPath: "/tmp/no-such-\(UUID().uuidString).wav")
        #expect(cache.key(for: missing, targetFormat: .asr16kMono) == nil)
    }

    @Test func manifestRoundTripAndRemoval() throws {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "manifest"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let entry = ConvertedAudioCache.ManifestEntry(
            digest: "abc123",
            sourcePath: "/tmp/source.wav",
            storedAt: Date(timeIntervalSince1970: 100)
        )
        try cache.updateManifest(adding: entry)
        let loaded = try cache.loadManifest()
        #expect(loaded["abc123"]?.sourcePath == "/tmp/source.wav")
        try cache.updateManifest(removingDigest: "abc123")
        #expect(try cache.loadManifest().isEmpty == true)
        try cache.updateManifest(removingDigest: "missing")  // no-op
    }
}

// MARK: - Backend dispatch

@Suite("Backend dispatch extended", .serialized, ResetSharedStateTrait())
struct BackendDispatchExtendedTests {
    @Test func makeTranscriberWhisperOnArm64() throws {
        #if arch(arm64)
        let t = try Backend.whisperCpp.makeTranscriber(model: "tiny")
        #expect(t.capabilities.defaultModelId == WhisperBackend.defaultModelId)
        #else
        #expect(Bool(false))
        #endif
    }

    @Test func appleSpeechRemoteModelsEmpty() async throws {
        #expect(try await Backend.appleSpeech.remoteModels().isEmpty == true)
    }

    @Test func parakeetInstalledModelsEmptyWhenCacheMissing() async throws {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            #expect(FileManager.default.fileExists(atPath: parakeetRoot.path) == true)
            let models = try Backend.parakeet.installedModels()
            #expect(models.isEmpty == true)
        }
    }

    @Test func whisperInstalledModelsFromTempBins() async throws {
        try await TestHelpers.withIsolatedModelCaches { _, whisperRoot in
            try FileManager.default.createDirectory(at: whisperRoot, withIntermediateDirectories: true)
            let bin = whisperRoot.appendingPathComponent("demo.bin")
            try Data("x".utf8).write(to: bin)
            let models = try Backend.whisperCpp.installedModels()
            #expect(models.contains(where: { $0.id == "demo" }) == true)
        }
    }

    @Test func parakeetRemoteModelsViaMock() async throws {
        let payload = """
            [{"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z"}]
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models?") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml") == true {
                    let info = """
                        {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z","siblings":[
                          {"rfilename":"model.mlmodelc/x","size":100}
                        ]}
                        """
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(info.utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let session = session
                let models = try await ParakeetBackend.remoteModels(session: session)
                #expect(models.isEmpty == false)
                #expect(models.contains(where: { $0.id == "v3" }) == true)
                _ = session
            }
        )
    }

    @Test func whisperRemoteModelsViaMock() async throws {
        let info = """
            {"id":"ggerganov/whisper.cpp","lastModified":"2024-01-01T00:00:00Z","siblings":[
              {"rfilename":"ggml-tiny.bin","size":1000}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(info.utf8))
            },
            { session in
                let models = try await WhisperBackend.remoteModels(session: session)
                #expect(models.contains(where: { $0.id == "tiny" }) == true)
            }
        )
    }
}

// MARK: - Parakeet registry

@Suite("ParakeetBackend registry extended", .serialized, ResetSharedStateTrait())
struct ParakeetRegistryExtendedTests {
    @Test func unknownIdHuggingFaceRepoId() {
        #expect(
            ParakeetBackend.huggingFaceRepoId(for: "custom-model")
                == "FluidInference/custom-model"
        )
    }

    @Test func repoFolderNameMatchesInstallFolder() {
        #expect(ParakeetBackend.repoFolderName(for: "v3") == ParakeetBackend.installFolderName(for: "v3"))
    }

    @Test func installedModelsFindsMlmodelcBundle() async throws {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let bundle = folder.appendingPathComponent("Encoder.mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data("weights".utf8).write(to: bundle.appendingPathComponent("w.bin"))
            let models = try ParakeetBackend.installedModels()
            #expect(models.count == 1)
            if models.count == 1 {
                #expect(models[0].id == "v3")
                #expect((models[0].sizeBytes ?? 0) > 0)
            }
        }
    }

    @Test func ensureLoadedUsesTestHook() async throws {
        let prior = ParakeetBackend.testLoadHook
        defer { ParakeetBackend.testLoadHook = prior }
        ParakeetBackend.testLoadHook = {
            MockParakeetSessionForHook(
                result: ASRResult(
                    text: "ok",
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

    @Test func installedModelsUsesUnknownFolderNameAsId() async throws {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("custom-unknown-model", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("X.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            let models = try ParakeetBackend.installedModels()
            #expect(models.contains(where: { $0.id == "custom-unknown-model" }) == true)
        }
    }

    @Test func publicRemoteModelsUsesSharedSessionOverride() async throws {
        let payload = """
            [{"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z"}]
            """
        let prior = ParakeetBackend.overrideRemoteModelsSession
        defer { ParakeetBackend.overrideRemoteModelsSession = prior }
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models?") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                let info = """
                    {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z","siblings":[]}
                    """
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(info.utf8))
            },
            { session in
                ParakeetBackend.overrideRemoteModelsSession = session
                let models = try await ParakeetBackend.remoteModels()
                #expect(models.isEmpty == false)
            }
        )
    }

    @Test func fetchRepoSizesUsesDefaultRepoInfoClosure() async throws {
        let repos = [HuggingFaceHub.HFRepo(id: "FluidInference/parakeet-tdt-0.6b-v3-coreml", lastModified: nil)]
        let info = """
            {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":null,"siblings":[
              {"rfilename":"a.bin","size":10}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(info.utf8))
            },
            { session in
                let sizes = try await ParakeetBackend.fetchRepoSizes(
                    for: repos,
                    session: session
                )
                #expect(sizes.count == 1)
            }
        )
    }

    @Test func transcribeV3IntegrationWhenInstalled() async throws {
        let path = ParakeetBackend.installPath(for: "v3")
        guard SuperscribeFS.containsCompiledCoreMLBundle(at: path) == true else { return }
        let prior = ParakeetBackend.testLoadHook
        ParakeetBackend.testLoadHook = nil
        defer { ParakeetBackend.testLoadHook = prior }
        let wav = try TestHelpers.makeTemp16kMonoFloatWAV(name: "pk-v3-it")
        defer { try? FileManager.default.removeItem(at: wav) }
        let backend = ParakeetBackend(model: "v3", injectedSession: nil)
        let samples = try AudioPreparer(for: backend.capabilities).loadAndConvert(url: wav)
        _ = try await backend.transcribe(
            samples: samples,
            segment: SpeechSegment(start: 0, end: min(1.0, Double(samples.count) / 16_000)),
            config: TranscriptionConfig(language: "en", model: "v3", prompt: nil)
        )
    }

    @Test func loadParakeetModelsIntoManagerWhenInstalled() async throws {
        let path = ParakeetBackend.installPath(for: "v3")
        guard SuperscribeFS.containsCompiledCoreMLBundle(at: path) == true else { return }
        let models = try await ParakeetBackend.loadAsrModelsFromFluidAudio(from: path, version: .v3)
        let mgr = AsrManager()
        try await ParakeetBackend.loadParakeetModelsIntoManager(mgr, models: models)
    }
}

private struct MockParakeetSessionForHook: ParakeetASRSession {
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

// MARK: - ModelDownloader

@Suite("ModelDownloader extended", .serialized, ResetSharedStateTrait())
struct ModelDownloaderExtendedTests {
    @Test func downloadProgressFractionNilWhenTotalUnknown() {
        let p = DownloadProgress(
            modelId: "m",
            backend: .parakeet,
            currentFile: "a",
            filesCompleted: 0,
            filesTotal: 1,
            bytesCompleted: 10,
            bytesTotal: nil,
            bytesPerSecond: nil
        )
        #expect(p.fraction == nil)
        let zero = DownloadProgress(
            modelId: "m",
            backend: .parakeet,
            currentFile: "a",
            filesCompleted: 0,
            filesTotal: 1,
            bytesCompleted: 0,
            bytesTotal: 0,
            bytesPerSecond: nil
        )
        #expect(zero.fraction == nil)
    }

    @Test func downloadFileBinNotFoundThrows() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"README.md","size":1}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(repoPayload.utf8))
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-missing-bin") { dir in
                    let model = RemoteModelInfo(
                        id: "missing",
                        repoId: repoId,
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.downloadFile(
                            model: model,
                            into: dir.appendingPathComponent("x.bin"),
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            }
        )
    }

    @Test func downloadRepoFileHttpError() async throws {
        _ = try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (resp, Data())
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-http") { dir in
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.downloadRepoFile(
                            repoId: "org/repo",
                            rfilename: "file.bin",
                            into: dir.appendingPathComponent("file.bin"),
                            expectedSize: 1,
                            session: session,
                            onProgress: nil
                        )
                    }
                }
            }
        )
    }

    @Test func streamBytesInvokesOnChunkForLargePayload() async throws {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: dest) }
        let payload = Array(repeating: UInt8(0xCD), count: 65_536 + 100)
        let stream = AsyncStream<UInt8> { continuation in
            for b in payload { continuation.yield(b) }
            continuation.finish()
        }
        final class ChunkSum: @unchecked Sendable {
            var total: Int64 = 0
        }
        let sum = ChunkSum()
        _ = try await ModelDownloader.streamBytes(
            from: stream,
            to: dest,
            sourceURL: URL(string: "https://example.com/big")!,
            expectedSize: Int64(payload.count)
        ) { chunk in
            sum.total += chunk
        }
        #expect(sum.total == Int64(payload.count))
    }

    @Test func downloadProgressFractionComputesRatio() {
        let p = DownloadProgress(
            modelId: "m",
            backend: .parakeet,
            currentFile: "a",
            filesCompleted: 0,
            filesTotal: 1,
            bytesCompleted: 50,
            bytesTotal: 100,
            bytesPerSecond: nil
        )
        #expect(p.fraction == 0.5)
    }

    @Test func downloadRepoFileNetworkError() async throws {
        _ = try await MockURLSessionHelpers.withMockHandler(
            { _ in throw URLError(.notConnectedToInternet) },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-net") { dir in
                    await #expect(throws: ModelInstallationError.self) {
                        try await ModelDownloader.downloadRepoFile(
                            repoId: "org/repo",
                            rfilename: "file.bin",
                            into: dir.appendingPathComponent("file.bin"),
                            expectedSize: 1,
                            session: session,
                            onProgress: nil
                        )
                    }
                }
            }
        )
    }

    @Test func downloadOneHttpErrorViaMultiFile() async throws {
        let repoId = "FluidInference/http-err"
        let repoPayload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"a.bin","size":3}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(repoPayload.utf8))
                }
                let resp = HTTPURLResponse(url: url, statusCode: 502, httpVersion: nil, headerFields: nil)!
                return (resp, Data())
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-one-http") { staging in
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
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                }
            }
        )
    }

    @Test func streamBytesCreateDirectoryFailure() async throws {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocked-\(UUID().uuidString)/nested/file.bin")
        let blocker = dest.deletingLastPathComponent().deletingLastPathComponent()
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
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

    @Test func streamBytesCannotOpenDestinationFile() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("parentfile-\(UUID().uuidString)")
        try Data("x".utf8).write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let dest = parent.appendingPathComponent("child.bin")
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

    @Test func streamBytesTransportError() async throws {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("err-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: dest) }
        struct FailingBytes: AsyncSequence {
            typealias Element = UInt8
            struct Iterator: AsyncIteratorProtocol {
                func next() async throws -> UInt8? {
                    throw URLError(.networkConnectionLost)
                }
            }
            func makeAsyncIterator() -> Iterator { Iterator() }
        }
        await #expect(throws: ModelInstallationError.self) {
            _ = try await ModelDownloader.streamBytes(
                from: FailingBytes(),
                to: dest,
                sourceURL: URL(string: "https://example.com/x")!,
                expectedSize: nil
            )
        }
    }
}

// MARK: - ModelInstaller

@Suite("ModelInstaller extended", .serialized, ResetSharedStateTrait())
struct ModelInstallerExtendedTests {
    @Test func parakeetAlreadyInstalledFastPath() async throws {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let tag = "pk-fast-\(UUID().uuidString.prefix(8))"
            let repoId = "FluidInference/\(tag)-coreml"
            let finalDir = ParakeetBackend.installPath(for: tag)
            try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: finalDir.appendingPathComponent("X.mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
            let model = RemoteModelInfo(
                id: tag,
                repoId: repoId,
                repoURL: URL(string: "https://huggingface.co/\(repoId)")!
            )
            let url = try await ModelInstaller.install(
                model: model,
                backend: .parakeet,
                session: URLSession.shared,
                onProgress: { _ in }
            )
            #expect(url.path == finalDir.path)
        }
    }

    @Test func whisperFullyInstalledFastPath() async throws {
        try await TestHelpers.withIsolatedModelCaches { _, whisperRoot in
            let tag = "wt-fast-\(UUID().uuidString.prefix(8))"
            let bin = WhisperBackend.installPath(for: tag)
            let encoder = WhisperBackend.encoderInstallPath(for: tag)
            try FileManager.default.createDirectory(at: whisperRoot, withIntermediateDirectories: true)
            try Data("bin".utf8).write(to: bin)
            try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
            let model = RemoteModelInfo(
                id: tag,
                repoId: WhisperBackend.huggingFaceRepoId,
                repoURL: URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")!
            )
            _ = try await ModelInstaller.install(
                model: model,
                backend: .whisperCpp,
                session: URLSession.shared,
                onProgress: { _ in }
            )
        }
    }

    @Test func removeInstalledAppleSpeechNoOp() throws {
        try ModelInstaller.removeInstalled(modelId: "any", backend: .appleSpeech)
    }

    @Test func removalPathsAppleSpeechEmpty() throws {
        #expect(try ModelInstaller.removalPaths(modelId: "any", backend: .appleSpeech).isEmpty == true)
    }

    @Test func removalPathsParakeetWhenPresent() async throws {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let tag = "pk-path-\(UUID().uuidString.prefix(8))"
            let dir = ParakeetBackend.installPath(for: tag)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let paths = try ModelInstaller.removalPaths(modelId: tag, backend: .parakeet)
            #expect(paths.count == 1)
            #expect(paths[0].path == dir.path)
        }
    }

    @Test func installUsesDefaultProgressHandler() async throws {
        try await TestHelpers.withIsolatedModelCaches { _, whisperRoot in
            let tag = "wt-def-\(UUID().uuidString.prefix(8))"
            let bin = WhisperBackend.installPath(for: tag)
            try FileManager.default.createDirectory(at: whisperRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let repoPayload = """
                {"id":"\(WhisperBackend.huggingFaceRepoId)","lastModified":null,"siblings":[
                  {"rfilename":"ggml-\(tag).bin","size":4}
                ]}
                """
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
                        return (resp, Data("ZZZZ".utf8))
                    }
                    throw URLError(.unsupportedURL)
                },
                { session in
                    let model = RemoteModelInfo(
                        id: tag,
                        repoId: WhisperBackend.huggingFaceRepoId,
                        repoURL: URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")!
                    )
                    _ = try await ModelInstaller.install(model: model, backend: .whisperCpp, session: session)
                }
            )
        }
    }

    @Test func whisperInstallDiscardsStagingWhenFinalDirExists() async throws {
        try await TestHelpers.withIsolatedModelCaches { _, whisperRoot in
            let tag = "wt-disc-\(UUID().uuidString.prefix(8))"
            let bin = WhisperBackend.installPath(for: tag)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let repoPayload = """
                {"id":"\(WhisperBackend.huggingFaceRepoId)","lastModified":null,"siblings":[
                  {"rfilename":"ggml-\(tag).bin","size":4}
                ]}
                """
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
                { session in
                    let model = RemoteModelInfo(
                        id: tag,
                        repoId: WhisperBackend.huggingFaceRepoId,
                        repoURL: URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")!
                    )
                    _ = try await ModelInstaller.install(
                        model: model,
                        backend: .whisperCpp,
                        session: session,
                        onProgress: { _ in }
                    )
                    #expect(SuperscribeFS.isExistingDirectory(at: bin) == true)
                }
            )
        }
    }

    @Test func installCleansUpStagingOnDownloadFailure() async throws {
        try await TestHelpers.withIsolatedModelCaches { _, whisperRoot in
            let tag = "wt-fail-\(UUID().uuidString.prefix(8))"
            let bin = WhisperBackend.installPath(for: tag)
            try await MockURLSessionHelpers.withMockHandler(
                { _ in throw URLError(.notConnectedToInternet) },
                { session in
                    let model = RemoteModelInfo(
                        id: tag,
                        repoId: WhisperBackend.huggingFaceRepoId,
                        repoURL: URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")!
                    )
                    await #expect(throws: Error.self) {
                        _ = try await ModelInstaller.install(
                            model: model,
                            backend: .whisperCpp,
                            session: session,
                            onProgress: { _ in }
                        )
                    }
                    let parent = bin.deletingLastPathComponent()
                    let stagingLeft = try FileManager.default.contentsOfDirectory(atPath: parent.path)
                        .contains(where: { $0.contains(".staging-") })
                    #expect(stagingLeft == false)
                }
            )
        }
    }

    @Test func preflightWalksUpToExistingAncestor() throws {
        let deep = FileManager.default.temporaryDirectory
            .appendingPathComponent("deep-\(UUID().uuidString)/a/b/c/model.bin")
        try ModelInstaller.preflightDiskSpace(requiredBytes: 1, installPath: deep)
    }

    @Test func preflightTightSpaceWarning() throws {
        let dir = try TestHelpers.makeTempDir(prefix: "preflight-tight")
        defer { try? FileManager.default.removeItem(at: dir) }
        let values = try dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values.volumeAvailableCapacityForImportantUsage, free > 1000 else { return }
        let required = Int64(Double(free) * 0.96)
        try ModelInstaller.preflightDiskSpace(requiredBytes: required, installPath: dir.appendingPathComponent("m.bin"))
    }

    @Test func isInstalledAppleSpeechAlwaysFalse() {
        let url = URL(fileURLWithPath: "/tmp/x")
        #expect(ModelInstaller.isInstalled(at: url, backend: .appleSpeech) == false)
    }
}

// MARK: - Merger / FS / Catalog / LoadOnce / HuggingFace

@Suite("Merger overlap policies", .serialized, ResetSharedStateTrait())
struct MergerOverlapTests {
    @Test func trimAndInterleavePreserveSegments() {
        let mergerTrim = Merger(config: .init(overlapPolicy: .trim))
        let mergerInter = Merger(config: .init(overlapPolicy: .interleave))
        let transcript = IntermediateTranscript(
            session: nil,
            tracks: [
                .init(
                    speaker: "A",
                    file: "a.wav",
                    segments: [.init(start: 0, end: 1, words: [])]
                )
            ],
            metadata: .init(
                backend: .parakeet,
                model: "m",
                language: nil,
                analyzer: .init(silenceThresholdDB: -40, minSilence: 0.5, padding: 0.15)
            )
        )
        #expect(mergerTrim.merge(transcript).count == 1)
        #expect(mergerInter.merge(transcript).count == 1)
    }

    @Test func coalesceRespectsMaxCueDuration() {
        let merger = Merger(config: .init(gapThreshold: 10, maxCueDuration: 1.0, maxCoalesceGap: 2.0))
        let transcript = IntermediateTranscript(
            session: nil,
            tracks: [
                .init(
                    speaker: "A",
                    file: "a.wav",
                    segments: [
                        .init(start: 0, end: 0.8, words: [TimedWord(text: "a", start: 0, end: 0.8)]),
                        .init(start: 1.0, end: 2.5, words: [TimedWord(text: "b", start: 1, end: 2.5)])
                    ]
                )
            ],
            metadata: .init(
                backend: .parakeet,
                model: "m",
                language: nil,
                analyzer: .init(silenceThresholdDB: -40, minSilence: 0.5, padding: 0.15)
            )
        )
        let merged = merger.merge(transcript)
        #expect(merged.count == 2)
    }
}

@Suite("SuperscribeFS extended", .serialized, ResetSharedStateTrait())
struct FilesystemExtendedTests {
    @Test func discardStagingPromotesWhenFinalAbsent() throws {
        let parent = try TestHelpers.makeTempDir(prefix: "atomic-promote")
        defer { try? FileManager.default.removeItem(at: parent) }
        let final = parent.appendingPathComponent("out.txt")
        let staging = parent.appendingPathComponent("out.txt.staging-test")
        try Data("new".utf8).write(to: staging)
        try SuperscribeFS.atomicReplace(staging: staging, final: final, policy: .discardStagingIfFinalExists)
        #expect(String(data: try Data(contentsOf: final), encoding: .utf8) == "new")
    }
}

@Suite("CatalogStore default path", .serialized, ResetSharedStateTrait())
struct CatalogStoreDefaultPathTests {
    @Test func fileURLWithoutOverride() {
        let prior = CatalogStore.overrideURL
        CatalogStore.overrideURL = nil
        defer { CatalogStore.overrideURL = prior }
        #expect(CatalogStore.fileURL.path.contains("catalog.json") == true)
    }
}

@Suite("LoadOnce cache hit", .serialized, ResetSharedStateTrait())
struct LoadOnceCacheHitTests {
    @Test func secondGetReturnsCachedValue() async throws {
        let loader = LoadOnce<String>()
        let counter = SequentialCounter()
        let first = try await loader.get {
            await counter.increment()
            return "cached"
        }
        let second = try await loader.get {
            await counter.increment()
            return "should-not-run"
        }
        #expect(first == "cached")
        #expect(second == "cached")
        #expect(await counter.value == 1)
    }
}

private actor SequentialCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@Suite("Final line coverage gaps", .serialized, ResetSharedStateTrait())
struct FinalLineCoverageGapTests {

    @Test func downloadProgressFractionWhenTotalKnown() {
        let progress = DownloadProgress(
            modelId: "m",
            backend: .parakeet,
            currentFile: "a.bin",
            filesCompleted: 0,
            filesTotal: 1,
            bytesCompleted: 50,
            bytesTotal: 100,
            bytesPerSecond: nil
        )
        #expect(progress.fraction == 0.5)
    }

    @Test func catalogStoreLoadThrowsOnInvalidJSON() throws {
        try TestHelpers.withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("catalog.json")
            try Data("{not-json".utf8).write(to: url)
            let prior = CatalogStore.overrideURL
            CatalogStore.overrideURL = url
            defer { CatalogStore.overrideURL = prior }
            #expect(throws: Error.self) {
                _ = try CatalogStore.load()
            }
        }
    }

    @Test func userConfigFileURLWithoutOverride() {
        let prior = UserConfig.overrideConfigFileURL
        UserConfig.overrideConfigFileURL = nil
        defer { UserConfig.overrideConfigFileURL = prior }
        #expect(UserConfig.configFileURL.path.hasSuffix("config.json") == true)
    }

    @Test func isExistingFileOnMissingPath() {
        let missing = URL(fileURLWithPath: "/no/such/\(UUID().uuidString).txt")
        #expect(SuperscribeFS.isExistingFile(at: missing) == false)
    }

    @Test func whisperInstalledModelsWhenCacheDirMissing() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-wh-\(UUID().uuidString)")
        let prior = SuperscribePaths.overrideWhisperModelCacheDirectory
        SuperscribePaths.overrideWhisperModelCacheDirectory = missing
        defer { SuperscribePaths.overrideWhisperModelCacheDirectory = prior }
        #expect(try WhisperBackend.installedModels().isEmpty == true)
    }

    @Test func totalInstallBytesNilWhenBinHasNoSize() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-zero.bin","size":null}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: "zero",
                    repoId: repoId,
                    totalSizeBytes: nil,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                )
                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == nil)
            }
        )
    }

    @Test func installIfNeededThrowsWhenZipIsCorrupt() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "bad-zip-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"\(zipName)","size":12}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/\(zipName)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data("not-a-zip-file".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    totalSizeBytes: 12,
                    fileCount: 1,
                    lastModified: nil,
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                )
                await #expect(throws: ModelInstallationError.self) {
                    try await WhisperEncoderInstaller.installIfNeeded(
                        model: model,
                        session: session,
                        onProgress: { _ in }
                    )
                }
            }
        )
    }

    @Test func cacheStoreAtomicReplaceFailureCleansStaging() throws {
        defer { SuperscribeKitTestHooks.forceCacheStoreAtomicReplaceFailure = false }
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "atomic-real"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let key = ConvertedAudioCache.CacheKey(
            sourcePath: "/tmp/source.wav",
            sourceSize: 1,
            sourceMtimeNanos: 1,
            formatKey: "f32-16000-1"
        )
        SuperscribeKitTestHooks.forceCacheStoreAtomicReplaceFailure = true
        #expect(throws: Error.self) {
            _ = try cache.store(samples: [0.1, 0.2], format: .asr16kMono, key: key)
        }
    }

    @Test func analyzerReadMonoFloat32SuccessPath() throws {
        let wav = try TestHelpers.makeTempSineWAV(
            name: "an-success",
            durationSeconds: 0.2,
            sampleRate: 48_000,
            channels: 2
        )
        defer { try? FileManager.default.removeItem(at: wav) }
        let (samples, rate) = try Analyzer.readMonoFloat32(from: wav)
        #expect(samples.isEmpty == false)
        #expect(rate == 48_000)
    }

    @Test func analyzerNilMonoChannelThrowsUnsupported() throws {
        defer { SuperscribeKitTestHooks.forceAnalyzerNilMonoChannel = false }
        let wav = try TestHelpers.makeTempSineWAV(
            name: "an-nil-channel",
            durationSeconds: 0.2,
            sampleRate: 48_000,
            channels: 2
        )
        defer { try? FileManager.default.removeItem(at: wav) }
        SuperscribeKitTestHooks.forceAnalyzerNilMonoChannel = true
        #expect(throws: AnalyzerError.self) { _ = try Analyzer.readMonoFloat32(from: wav) }
    }

    @Test func stagingURLWithExplicitLabel() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("weights/file.bin")
        let staging = SuperscribeFS.stagingURL(beside: base, label: "custom-label")
        #expect(staging.lastPathComponent.hasPrefix("custom-label.staging-") == true)
    }

    @Test func catalogStoreFileURLHonorsOverride() throws {
        try TestHelpers.withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("catalog.json")
            let prior = CatalogStore.overrideURL
            CatalogStore.overrideURL = url
            defer { CatalogStore.overrideURL = prior }
            #expect(CatalogStore.fileURL == url)
        }
    }

    @Test func catalogStoreUpdateWhenLoadFails() throws {
        try TestHelpers.withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("catalog.json")
            try Data("{bad".utf8).write(to: url)
            let prior = CatalogStore.overrideURL
            CatalogStore.overrideURL = url
            defer { CatalogStore.overrideURL = prior }
            try CatalogStore.update(
                CatalogEntry(fetchedAt: Date(), models: []),
                for: .parakeet
            )
            let loaded = try CatalogStore.load()
            #expect(loaded.entry(for: .parakeet) != nil)
        }
    }

    @Test func downloadWithoutSubpathUsesRootFilenames() async throws {
        let repoId = "FluidInference/root-files"
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"model.bin","size":4}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/model.bin") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data("data".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-root") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        subpath: nil,
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    try await ModelDownloader.download(
                        model: model,
                        backend: .parakeet,
                        into: staging,
                        session: session,
                        onProgress: { _ in }
                    )
                    #expect(FileManager.default.fileExists(atPath: staging.appendingPathComponent("model.bin").path) == true)
                }
            }
        )
    }

    @Test func fetchRepoSizesNilTotalWhenSizesMissing() async throws {
        let repos = [HuggingFaceHub.HFRepo(id: "FluidInference/empty-sizes", lastModified: nil)]
        let info = """
            {"id":"FluidInference/empty-sizes","lastModified":null,"siblings":[
              {"rfilename":"a.bin","size":null}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(info.utf8))
            },
            { session in
                let sizes = try await ParakeetBackend.fetchRepoSizes(
                    for: repos,
                    session: session
                )
                #expect(sizes["FluidInference/empty-sizes"]?.totalBytes == nil)
            }
        )
    }

    @Test func encoderBaseIdPassthroughVariants() {
        #expect(WhisperBackend.encoderBaseId(for: "ab") == "ab")
        #expect(WhisperBackend.encoderBaseId(for: "base") == "base")
    }

    @Test func cacheStoreOpenFailureThrows() throws {
        defer { SuperscribeKitTestHooks.forceCacheStoreOpenFailure = false }
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "cache-open"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let key = ConvertedAudioCache.CacheKey(
            sourcePath: "/tmp/x.wav",
            sourceSize: 1,
            sourceMtimeNanos: 1,
            formatKey: "f32-16000-1"
        )
        SuperscribeKitTestHooks.forceCacheStoreOpenFailure = true
        #expect(throws: AudioPreparerError.self) {
            _ = try cache.store(samples: [0.1], format: .asr16kMono, key: key)
        }
    }

    @Test func downloadProgressFractionCapsAtOne() {
        let progress = DownloadProgress(
            modelId: "m",
            backend: .parakeet,
            currentFile: "a.bin",
            filesCompleted: 0,
            filesTotal: 1,
            bytesCompleted: 200,
            bytesTotal: 100,
            bytesPerSecond: nil
        )
        #expect(progress.fraction == 1.0)
    }

    @Test func convertedAudioCacheDefaultRootInit() throws {
        let cache = ConvertedAudioCache()
        #expect(cache.root.path.contains("audio") == true)
    }

    @Test func cacheKeyDigestIsStable() {
        let key = ConvertedAudioCache.CacheKey(
            sourcePath: "/tmp/a.wav",
            sourceSize: 100,
            sourceMtimeNanos: 1,
            formatKey: "f32-16000-1"
        )
        #expect(key.digest.count == 64)
        #expect(
            key.digest
                == ConvertedAudioCache.CacheKey(
                    sourcePath: "/tmp/a.wav",
                    sourceSize: 100,
                    sourceMtimeNanos: 1,
                    formatKey: "f32-16000-1"
                ).digest)
    }

    @Test func containsCompiledCoreMLBundleFalseForPlainFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(SuperscribeFS.containsCompiledCoreMLBundle(at: file) == false)
    }

    @Test func whisperRemoteModelsUsesDefaultSessionWhenOverrideNil() async throws {
        let payload = """
            {"id":"ggerganov/whisper.cpp","lastModified":null,"siblings":[
              {"rfilename":"ggml-tiny.bin","size":1}
            ]}
            """
        let priorOverride = WhisperBackend.overrideRemoteModelsSession
        let priorDefault = WhisperBackend.defaultRemoteModelsSession
        defer {
            WhisperBackend.overrideRemoteModelsSession = priorOverride
            WhisperBackend.defaultRemoteModelsSession = priorDefault
        }
        WhisperBackend.overrideRemoteModelsSession = nil
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(payload.utf8))
            },
            { session in
                WhisperBackend.defaultRemoteModelsSession = session
                let models = try await WhisperBackend.remoteModels()
                #expect(models.contains(where: { $0.id == "tiny" }) == true)
            }
        )
    }

    @Test func parakeetRemoteModelsUsesDefaultSessionWhenOverrideNil() async throws {
        let listPayload = """
            [{"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z"}]
            """
        let priorOverride = ParakeetBackend.overrideRemoteModelsSession
        let priorDefault = ParakeetBackend.defaultRemoteModelsSession
        defer {
            ParakeetBackend.overrideRemoteModelsSession = priorOverride
            ParakeetBackend.defaultRemoteModelsSession = priorDefault
        }
        ParakeetBackend.overrideRemoteModelsSession = nil
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models?") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(listPayload.utf8))
                }
                let info = """
                    {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z","siblings":[]}
                    """
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(info.utf8))
            },
            { session in
                ParakeetBackend.defaultRemoteModelsSession = session
                let models = try await ParakeetBackend.remoteModels()
                #expect(models.isEmpty == false)
            }
        )
    }

    @Test func totalInstallBytesAddsEncoderZipSize() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "enc-add-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-\(tag).bin","size":100},
              {"rfilename":"\(zipName)","size":40}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    totalSizeBytes: nil,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                )
                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == 140)
            }
        )
    }

    @Test func totalInstallBytesIgnoresEncoderZipWithNilSize() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "enc-nil-\(UUID().uuidString.prefix(6))"
        let zipName = WhisperBackend.encoderZipRemoteName(for: tag)
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-\(tag).bin","size":100},
              {"rfilename":"\(zipName)","size":null}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    totalSizeBytes: nil,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                )
                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == 100)
            }
        )
    }

    @Test func whisperBackendForceUnavailable() {
        let prior = WhisperBackend.testForceUnavailable
        defer { WhisperBackend.testForceUnavailable = prior }
        WhisperBackend.testForceUnavailable = true
        #expect(WhisperBackend.isAvailable == false)
    }

    @Test func parakeetRepoFolderNameUnknownId() {
        #expect(ParakeetBackend.repoFolderName(for: "custom-x") == "custom-x")
    }

    @Test func isExistingDirectoryFalseForPlainFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-dir-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(SuperscribeFS.isExistingDirectory(at: file) == false)
    }

    @Test func downloadSubpathWithoutTrailingSlash() async throws {
        let repoId = "FluidInference/subpath-no-slash"
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"weights/a.bin","size":3}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/weights/a.bin") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data("abc".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-sub") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        subpath: "weights",
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    try await ModelDownloader.download(
                        model: model,
                        backend: .parakeet,
                        into: staging,
                        session: session,
                        onProgress: { _ in }
                    )
                    #expect(FileManager.default.fileExists(atPath: staging.appendingPathComponent("a.bin").path) == true)
                }
            }
        )
    }

    @Test func cacheKeyNilForMissingFile() throws {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "key-missing"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let missing = URL(fileURLWithPath: "/no/such/\(UUID().uuidString).wav")
        #expect(cache.key(for: missing, targetFormat: .asr16kMono) == nil)
    }

    @Test func updateManifestRemovingAbsentDigestIsNoOp() throws {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "manifest-rm"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        try cache.updateManifest(removingDigest: "absent-digest")
    }

    @Test func containsCompiledCoreMLBundleWhenListingFails() throws {
        defer { SuperscribeKitTestHooks.forceContentsOfDirectoryFailure = false }
        let dir = try TestHelpers.makeTempDir(prefix: "ml-listing-fail")
        defer { try? FileManager.default.removeItem(at: dir) }
        SuperscribeKitTestHooks.forceContentsOfDirectoryFailure = true
        #expect(SuperscribeFS.containsCompiledCoreMLBundle(at: dir) == false)
    }

    @Test func loadManifestDedupesDuplicateDigests() throws {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "manifest-dup"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
        let json = """
            [
              {"digest":"dup","sourcePath":"/a.wav","storedAt":"2024-01-01T00:00:00Z"},
              {"digest":"dup","sourcePath":"/b.wav","storedAt":"2024-01-02T00:00:00Z"}
            ]
            """
        try Data(json.utf8).write(to: cache.manifestURL)
        let loaded = try cache.loadManifest()
        #expect(loaded.count == 1)
        #expect(loaded["dup"]?.sourcePath == "/b.wav")
    }

    @Test func updateManifestAddingWhenLoadFailsUsesEmptyBase() throws {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "manifest-add-bad"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
        try Data("{bad".utf8).write(to: cache.manifestURL)
        let entry = ConvertedAudioCache.ManifestEntry(
            digest: "new-digest",
            sourcePath: "/tmp/x.wav",
            storedAt: Date(timeIntervalSince1970: 0)
        )
        try cache.updateManifest(adding: entry)
        let loaded = try cache.loadManifest()
        #expect(loaded["new-digest"]?.sourcePath == "/tmp/x.wav")
    }

    @Test func updateManifestRemovingWhenLoadFailsIsNoOp() throws {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "manifest-rm-bad"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
        try Data("{bad".utf8).write(to: cache.manifestURL)
        try cache.updateManifest(removingDigest: "missing")
    }

    @Test func downloadUsesModelTotalWhenFileSizeUnknown() async throws {
        let repoId = "FluidInference/unknown-size"
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"model.bin","size":null}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/model.bin") == true {
                    let resp = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Length": "4"]
                    )!
                    return (resp, Data("data".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-unknown-size") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        totalSizeBytes: 99,
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    nonisolated(unsafe) var lastProgress: DownloadProgress?
                    try await ModelDownloader.download(
                        model: model,
                        backend: .parakeet,
                        into: staging,
                        session: session,
                        onProgress: { lastProgress = $0 }
                    )
                    #expect(lastProgress?.bytesTotal == 99)
                }
            }
        )
    }

    @Test func downloadRepoFileUsesResponseContentLength() async throws {
        let repoId = WhisperBackend.huggingFaceRepoId
        let name = "probe-\(UUID().uuidString.prefix(6)).bin"
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "5"]
                )!
                return (resp, Data("12345".utf8))
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "repo-file-len") { dir in
                    let dest = dir.appendingPathComponent(name)
                    nonisolated(unsafe) var lastTotal: Int64?
                    try await ModelDownloader.downloadRepoFile(
                        repoId: repoId,
                        rfilename: name,
                        into: dest,
                        expectedSize: 99,
                        session: session,
                        onProgress: { _, total in lastTotal = total }
                    )
                    #expect(lastTotal == 5)
                }
            }
        )
    }

    @Test func whisperInvokeLogSuppressorsForTesting() {
        WhisperBackend.invokeLogSuppressorsForTesting()
    }

    @Test func parakeetInstalledModelsSkipsFileEntry() async throws {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let file = parakeetRoot.appendingPathComponent("not-a-directory")
            try Data("x".utf8).write(to: file)
            #expect(try ParakeetBackend.installedModels().isEmpty == true)
        }
    }

    @Test func parakeetInstalledModelsSkipsDirectoryWithoutBundle() async throws {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("empty-model", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #expect(try ParakeetBackend.installedModels().isEmpty == true)
        }
    }

    @Test func parakeetMapReposUsesBareNameWhenNoSlash() {
        let repos = [HuggingFaceHub.HFRepo(id: "bare-repo-name", lastModified: nil)]
        let mapped = ParakeetBackend.mapRepos(repos)
        #expect(mapped.count == 1)
        #expect(mapped[0].id == "bare-repo-name")
    }

    @Test func parakeetMapReposFallsBackWhenSplitIsEmpty() {
        let repos = [HuggingFaceHub.HFRepo(id: "/", lastModified: nil)]
        let mapped = ParakeetBackend.mapRepos(repos)
        #expect(mapped.count == 1)
        #expect(mapped[0].id == "/")
    }

    @Test func downloadSkipsSiblingWithEmptyRelativePath() async throws {
        let repoId = "FluidInference/empty-rel"
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"weights/","size":null},
              {"rfilename":"weights/a.bin","size":3}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let s = url.absoluteString
                if s.contains("/api/models/\(repoId)") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/weights/a.bin") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (resp, Data("abc".utf8))
                }
                throw URLError(.unsupportedURL)
            },
            { session in
                try await TestHelpers.withTempDirectory(prefix: "dl-empty-rel") { staging in
                    let model = RemoteModelInfo(
                        id: "m",
                        repoId: repoId,
                        subpath: "weights",
                        repoURL: URL(string: "https://huggingface.co/\(repoId)")!
                    )
                    try await ModelDownloader.download(
                        model: model,
                        backend: .parakeet,
                        into: staging,
                        session: session,
                        onProgress: { _ in }
                    )
                    #expect(FileManager.default.fileExists(atPath: staging.appendingPathComponent("a.bin").path) == true)
                }
            }
        )
    }
}

@Suite("HuggingFaceHub date decode", .serialized, ResetSharedStateTrait())
struct HuggingFaceHubDateDecodeTests {
    @Test func badDateStringThrowsDecodingError() async throws {
        let payload = """
            [{"id":"FluidInference/x","lastModified":"not-a-date"}]
            """
        _ = try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(payload.utf8))
            },
            { session in
                await #expect(throws: HuggingFaceHub.Error.self) {
                    _ = try await HuggingFaceHub.listAuthorRepos(
                        author: "FluidInference",
                        search: nil,
                        session: session
                    )
                }
            }
        )
    }
}
