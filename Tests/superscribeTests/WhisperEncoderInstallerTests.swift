import Foundation
import Testing

@testable import SuperscribeKit

@Suite("WhisperEncoderInstaller", .serialized, ResetSharedStateTrait())
struct WhisperEncoderInstallerTests {
    @Test func skipsWhenEncoderAlreadyInstalled() async throws {
        let modelId = "base"
        let encoderPath = WhisperBackend.encoderInstallPath(for: modelId)
        try FileManager.default.createDirectory(at: encoderPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: encoderPath) }

        let model = RemoteModelInfo(
            id: modelId,
            repoId: WhisperBackend.huggingFaceRepoId,
            totalSizeBytes: 1,
            fileCount: 1,
            lastModified: nil,
            repoURL: URL(string: "https://huggingface.co/\(WhisperBackend.huggingFaceRepoId)")!
        )

        let probe = ProgressTickProbe()
        try await WhisperEncoderInstaller.installIfNeeded(model: model) { _ in
            probe.tick()
        }
        #expect(probe.count == 0)
    }

    @Test func downloadProgressReportingBuildsExpectedShape() throws {
        let probe = ProgressCapture()
        DownloadProgressReporting.emit(
            modelId: "base",
            backend: .whisperCpp,
            currentFile: "ggml-base-encoder.mlmodelc.zip",
            filesCompleted: 1,
            filesTotal: 2,
            bytesCompleted: 50,
            bytesTotal: 100
        ) { probe.store($0) }

        let progress = try #require(probe.value)
        #expect(progress.modelId == "base")
        #expect(progress.backend == .whisperCpp)
        #expect(progress.filesCompleted == 1)
        #expect(progress.filesTotal == 2)
        #expect(progress.bytesCompleted == 50)
        #expect(progress.bytesTotal == 100)
    }
}

private final class ProgressTickProbe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    func tick() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value: DownloadProgress?
    func store(_ progress: DownloadProgress) {
        lock.lock()
        value = progress
        lock.unlock()
    }
}
