import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Final line coverage gaps", .serialized, ResetSharedStateTrait())
struct FinalLineCoverageGapTests {

    @Test func downloadProgressFractionWhenTotalKnown() throws -> Void {
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

    @Test func catalogStoreLoadThrowsOnInvalidJSON() throws -> Void {
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

    @Test func userConfigFileURLWithoutOverride() throws -> Void {
        let prior = UserConfig.overrideConfigFileURL
        UserConfig.overrideConfigFileURL = nil
        defer { UserConfig.overrideConfigFileURL = prior }
        #expect(UserConfig.configFileURL.path.hasSuffix("config.json") == true)
    }

    @Test func isExistingFileOnMissingPath() throws -> Void {
        let missing = URL(fileURLWithPath: "/no/such/\(UUID().uuidString).txt")
        #expect(SuperscribeFS.isExistingFile(at: missing) == false)
    }

    @Test func whisperInstalledModelsWhenCacheDirMissing() throws -> Void {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-wh-\(UUID().uuidString)")
        let prior = SuperscribePaths.overrideWhisperModelCacheDirectory
        SuperscribePaths.overrideWhisperModelCacheDirectory = missing
        defer { SuperscribePaths.overrideWhisperModelCacheDirectory = prior }
        #expect(try WhisperBackend.installedModels().isEmpty == true)
    }

    @Test func totalInstallBytesNilWhenBinSizeZero() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let tag = "zero-size-\(UUID().uuidString.prefix(6))"
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-\(tag).bin","size":0}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    totalSizeBytes: nil,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )
                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == nil)
            }
        )
    }

    @Test func totalInstallBytesNilWhenBinHasNoSize() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let payload = """
            {"id":"\(repoId)","lastModified":null,"siblings":[
              {"rfilename":"ggml-zero.bin","size":null}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: "zero",
                    repoId: repoId,
                    totalSizeBytes: nil,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )
                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == nil)
            }
        )
    }

    @Test func installIfNeededThrowsWhenZipIsCorrupt() async throws -> Void {
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
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/\(zipName)") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
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
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
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

    @Test func cacheStoreAtomicReplaceFailureCleansStaging() throws -> Void {
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

    @Test func analyzerReadMonoFloat32SuccessPath() throws -> Void {
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

    @Test func stagingURLWithExplicitLabel() throws -> Void {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("weights/file.bin")
        let staging = SuperscribeFS.stagingURL(beside: base, label: "custom-label")
        #expect(staging.lastPathComponent.hasPrefix("custom-label.staging-") == true)
    }

    @Test func catalogStoreFileURLHonorsOverride() throws -> Void {
        try TestHelpers.withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("catalog.json")
            let prior = CatalogStore.overrideURL
            CatalogStore.overrideURL = url
            defer { CatalogStore.overrideURL = prior }
            #expect(CatalogStore.fileURL == url)
        }
    }

    @Test func catalogStoreUpdateWhenLoadFails() throws -> Void {
        try TestHelpers.withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("catalog.json")
            try Data("{bad".utf8).write(to: url)
            let prior = CatalogStore.overrideURL
            CatalogStore.overrideURL = url
            defer { CatalogStore.overrideURL = prior }
            #expect(throws: DecodingError.self) {
                try CatalogStore.update(CatalogEntry(fetchedAt: Date(), models: []), for: .parakeet)
            }
            #expect(try Data(contentsOf: url) == Data("{bad".utf8))
        }
    }

    @Test func downloadWithoutSubpathUsesRootFilenames() async throws -> Void {
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
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/model.bin") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
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
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
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

    @Test func fetchRepoSizesNilTotalWhenSizesMissing() async throws -> Void {
        let repos = [HuggingFaceHub.HFRepo(id: "FluidInference/empty-sizes", lastModified: nil)]
        let info = """
            {"id":"FluidInference/empty-sizes","lastModified":null,"siblings":[
              {"rfilename":"a.bin","size":null}
            ]}
            """
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
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

    @Test func encoderBaseIdPassthroughVariants() throws -> Void {
        #expect(WhisperBackend.encoderBaseId(for: "ab") == "ab")
        #expect(WhisperBackend.encoderBaseId(for: "base") == "base")
    }

    @Test func cacheStoreOpenFailureThrows() throws -> Void {
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

    @Test func downloadProgressFractionCapsAtOne() throws -> Void {
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

    @Test func convertedAudioCacheDefaultRootInit() throws -> Void {
        let cache = ConvertedAudioCache()
        #expect(cache.root.path.contains("audio") == true)
    }

    @Test func cacheKeyDigestIsStable() throws -> Void {
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

    @Test func containsCompiledCoreMLBundleFalseForPlainFile() throws -> Void {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(SuperscribeFS.containsCompiledCoreMLBundle(at: file) == false)
    }

    @Test func whisperRemoteModelsUsesDefaultSessionWhenOverrideNil() async throws -> Void {
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
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                WhisperBackend.defaultRemoteModelsSession = session
                let models = try await WhisperBackend.remoteModels()
                #expect(models.contains(where: { $0.id == "tiny" }) == true)
            }
        )
    }

    @Test func parakeetRemoteModelsUsesDefaultSessionWhenOverrideNil() async throws -> Void {
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
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(listPayload.utf8))
                }
                let info = """
                    {"id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","lastModified":"2024-01-01T00:00:00Z","siblings":[]}
                    """
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(info.utf8))
            },
            { session in
                ParakeetBackend.defaultRemoteModelsSession = session
                let models = try await ParakeetBackend.remoteModels()
                #expect(models.isEmpty == false)
            }
        )
    }

    @Test func totalInstallBytesAddsEncoderZipSize() async throws -> Void {
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
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    totalSizeBytes: nil,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )
                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == 140)
            }
        )
    }

    @Test func totalInstallBytesIgnoresEncoderZipWithNilSize() async throws -> Void {
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
                let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                return (resp, Data(payload.utf8))
            },
            { session in
                let model = RemoteModelInfo(
                    id: tag,
                    repoId: repoId,
                    totalSizeBytes: nil,
                    fileCount: nil,
                    lastModified: nil,
                    repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
                )
                let total = try await WhisperEncoderInstaller.totalInstallBytes(
                    model: model,
                    session: session
                )
                #expect(total == 100)
            }
        )
    }

    @Test func whisperBackendForceUnavailable() throws -> Void {
        let prior = WhisperBackend.testForceUnavailable
        defer { WhisperBackend.testForceUnavailable = prior }
        WhisperBackend.testForceUnavailable = true
        #expect(WhisperBackend.isAvailable == false)
    }

    @Test func parakeetRepoFolderNameUnknownId() -> Void {
        #expect(throws: UnsupportedModelError.self) { _ = try ParakeetBackend.installFolderName(for: "custom-x") }
    }

    @Test func isExistingDirectoryFalseForPlainFile() throws -> Void {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-dir-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(SuperscribeFS.isExistingDirectory(at: file) == false)
    }

    @Test func downloadSubpathWithoutTrailingSlash() async throws -> Void {
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
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/weights/a.bin") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
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
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
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

    @Test func cacheKeyNilForMissingFile() throws -> Void {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "key-missing"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let missing = URL(fileURLWithPath: "/no/such/\(UUID().uuidString).wav")
        #expect(cache.key(for: missing, targetFormat: .asr16kMono) == nil)
    }

    @Test func updateManifestRemovingAbsentDigestIsNoOp() throws -> Void {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "manifest-rm"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        try cache.updateManifest(removingDigest: "absent-digest")
    }

    @Test func containsCompiledCoreMLBundleWhenListingFails() throws -> Void {
        defer { SuperscribeKitTestHooks.forceContentsOfDirectoryFailure = false }
        let dir = try TestHelpers.makeTempDir(prefix: "ml-listing-fail")
        defer { try? FileManager.default.removeItem(at: dir) }
        SuperscribeKitTestHooks.forceContentsOfDirectoryFailure = true
        #expect(SuperscribeFS.containsCompiledCoreMLBundle(at: dir) == false)
    }

    @Test func loadManifestDedupesDuplicateDigests() throws -> Void {
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

    @Test func updateManifestAddingWhenLoadFailsUsesEmptyBase() throws -> Void {
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

    @Test func updateManifestRemovingWhenLoadFailsIsNoOp() throws -> Void {
        let cache = try ConvertedAudioCache(root: TestHelpers.makeTempDir(prefix: "manifest-rm-bad"))
        defer { try? FileManager.default.removeItem(at: cache.root) }
        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
        try Data("{bad".utf8).write(to: cache.manifestURL)
        try cache.updateManifest(removingDigest: "missing")
    }

    @Test func downloadUsesModelTotalWhenFileSizeUnknown() async throws -> Void {
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
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/model.bin") == true {
                    let resp =
                        (try #require(
                            HTTPURLResponse(
                                url: url,
                                statusCode: 200,
                                httpVersion: nil,
                                headerFields: ["Content-Length": "4"]
                            )))
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
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
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

    @Test func downloadRepoFileUsesResponseContentLength() async throws -> Void {
        let repoId = WhisperBackend.huggingFaceRepoId
        let name = "probe-\(UUID().uuidString.prefix(6)).bin"
        try await MockURLSessionHelpers.withMockHandler(
            { req in
                guard let url = req.url else { throw URLError(.badURL) }
                let resp =
                    (try #require(
                        HTTPURLResponse(
                            url: url,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: ["Content-Length": "5"]
                        )))
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
                        expectedSize: nil,
                        session: session,
                        onProgress: { _, total in lastTotal = total }
                    )
                    #expect(lastTotal == 5)
                }
            }
        )
    }

    @Test func whisperInvokeLogSuppressorsForTesting() throws -> Void {
        WhisperBackend.invokeLogSuppressorsForTesting()
    }

    @Test func parakeetInstalledModelsSkipsFileEntry() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let file = parakeetRoot.appendingPathComponent("not-a-directory")
            try Data("x".utf8).write(to: file)
            #expect(try ParakeetBackend.installedModels().isEmpty == true)
        }
    }

    @Test func parakeetInstalledModelsSkipsDirectoryWithoutBundle() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let folder = parakeetRoot.appendingPathComponent("empty-model", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #expect(try ParakeetBackend.installedModels().isEmpty == true)
        }
    }

    @Test func parakeetMapReposUsesBareNameWhenNoSlash() throws -> Void {
        let repos = [HuggingFaceHub.HFRepo(id: "bare-repo-name", lastModified: nil)]
        let mapped = try ParakeetBackend.mapRepos(repos)
        #expect(mapped.isEmpty == true)
    }

    @Test func parakeetMapReposFallsBackWhenSplitIsEmpty() throws -> Void {
        let repos = [HuggingFaceHub.HFRepo(id: "/", lastModified: nil)]
        let mapped = try ParakeetBackend.mapRepos(repos)
        #expect(mapped.isEmpty == true)
    }

    @Test func downloadSkipsSiblingWithEmptyRelativePath() async throws -> Void {
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
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                    return (resp, Data(payload.utf8))
                }
                if s.contains("/resolve/main/weights/a.bin") == true {
                    let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
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
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
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
