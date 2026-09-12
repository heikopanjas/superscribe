import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

// MARK: - ModelInstaller

@Suite("ModelInstaller extended", .serialized, ResetSharedStateTrait())
struct ModelInstallerExtendedTests {
    @Test func parakeetAlreadyInstalledFastPath() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let tag = "v3"
            let repoId = try ParakeetBackend.huggingFaceRepoId(for: tag)
            let finalDir = try ParakeetBackend.installPath(for: tag)
            try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
            try TestHelpers.makeParakeetInstallation(at: finalDir)
            let model = RemoteModelInfo(
                id: tag,
                repoId: repoId,
                repoURL: (try #require(URL(string: "https://huggingface.co/\(repoId)")))
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

    @Test func whisperFullyInstalledFastPath() async throws -> Void {
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
                repoURL: (try #require(URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")))
            )
            _ = try await ModelInstaller.install(
                model: model,
                backend: .whisperCpp,
                session: URLSession.shared,
                onProgress: { _ in }
            )
        }
    }

    @Test func removeInstalledAppleSpeechReleasesLocale() async throws -> Void {
        if #available(macOS 26, *) {
            await confirmation("Requested locale was released") { released in
                await AppleSpeechLiveAPI.$releaseOperation.withValue(
                    { locale in
                        #expect(AppleSpeechSupport.normalizeLocaleId(locale.identifier) == "en-US")
                        released()
                    },
                    operation: {
                        do {
                            try await ModelInstaller.removeInstalled(modelId: "en-US", backend: .appleSpeech)
                        }
                        catch {
                            Issue.record(error)
                        }
                    })
            }
        }
    }

    @Test func removalPathsAppleSpeechEmptyWhenNotInstalled() async throws -> Void {
        if #available(macOS 26, *) {
            AppleSpeechLiveAPI.testInstalledLocaleIds = []
            defer { AppleSpeechLiveAPI.testInstalledLocaleIds = nil }
            #expect(try await ModelInstaller.removalPaths(modelId: "any", backend: .appleSpeech).isEmpty == true)
        }
    }

    @Test func removalPathsParakeetWhenPresent() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { parakeetRoot, _ in
            let tag = "v3"
            let dir = try ParakeetBackend.installPath(for: tag)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let paths = try await ModelInstaller.removalPaths(modelId: tag, backend: .parakeet)
            #expect(paths.count == 1)
            #expect(paths[0].path == dir.path)
        }
    }

    @Test func installUsesDefaultProgressHandler() async throws -> Void {
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
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data(repoPayload.utf8))
                    }
                    if s.contains("/resolve/main/ggml-\(tag).bin") == true {
                        let resp = (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
                        return (resp, Data("ZZZZ".utf8))
                    }
                    throw URLError(.unsupportedURL)
                },
                { session in
                    let model = RemoteModelInfo(
                        id: tag,
                        repoId: WhisperBackend.huggingFaceRepoId,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")))
                    )
                    _ = try await ModelInstaller.install(model: model, backend: .whisperCpp, session: session)
                }
            )
        }
    }

    @Test func whisperInstallRepairsDirectoryAtBinaryPath() async throws -> Void {
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
                    _ = try await ModelInstaller.install(
                        model: model,
                        backend: .whisperCpp,
                        session: session,
                        onProgress: { _ in }
                    )
                    #expect(SuperscribeFS.isExistingFile(at: bin) == true)
                }
            )
        }
    }

    @Test func installCleansUpStagingOnDownloadFailure() async throws -> Void {
        try await TestHelpers.withIsolatedModelCaches { _, whisperRoot in
            let tag = "wt-fail-\(UUID().uuidString.prefix(8))"
            let bin = WhisperBackend.installPath(for: tag)
            try await MockURLSessionHelpers.withMockHandler(
                { _ in throw URLError(.notConnectedToInternet) },
                { session in
                    let model = RemoteModelInfo(
                        id: tag,
                        repoId: WhisperBackend.huggingFaceRepoId,
                        repoURL: (try #require(URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")))
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

    @Test func preflightWalksUpToExistingAncestor() throws -> Void {
        let deep = FileManager.default.temporaryDirectory
            .appendingPathComponent("deep-\(UUID().uuidString)/a/b/c/model.bin")
        try ModelInstaller.preflightDiskSpace(requiredBytes: 1, installPath: deep)
    }

    @Test func preflightTightSpaceWarning() throws -> Void {
        let dir = try TestHelpers.makeTempDir(prefix: "preflight-tight")
        defer { try? FileManager.default.removeItem(at: dir) }
        let values = try dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values.volumeAvailableCapacityForImportantUsage, free > 1000 else { return }
        let required = Int64(Double(free) * 0.96)
        try ModelInstaller.preflightDiskSpace(requiredBytes: required, installPath: dir.appendingPathComponent("m.bin"))
    }

    @Test func isInstalledAppleSpeechFalseForInvalidMarker() async -> Void {
        let url = URL(fileURLWithPath: "/tmp/x")
        #expect(await ModelInstaller.isInstalled(at: url, backend: .appleSpeech) == false)
    }
}
