import Foundation
import Testing

@testable import SuperscribeKit

@Suite("WhisperEncoderInstaller networking", .serialized, ResetSharedStateTrait())
struct WhisperEncoderInstallerNetworkTests {
    @Test func totalInstallBytesSumsBinAndEncoderZip() async throws -> Void {
        let fixture = try WhisperDownloadFixture(binary: .init(Data(repeating: 0, count: 100)), encoder: .init(Data(repeating: 0, count: 40)))
        try await fixture.withSession { session in
            let total = try await WhisperEncoderInstaller.totalInstallBytes(model: fixture.model, session: session)
            #expect(total == 140)
        }
    }

    @Test func totalInstallBytesFallsBackWhenBinSiblingMissing() async throws -> Void {
        let fixture = try WhisperDownloadFixture(catalogSize: 999)
        try await fixture.withSession { session in
            let total = try await WhisperEncoderInstaller.totalInstallBytes(model: fixture.model, session: session)
            #expect(total == 999)
        }
    }

    @Test func installIfNeededNoZipSiblingReturnsEarly() async throws -> Void {
        let fixture = try WhisperDownloadFixture(binary: .init(Data(repeating: 0, count: 10)))
        try await fixture.withSession { session in
            try await WhisperEncoderInstaller.installIfNeeded(model: fixture.model, session: session, onProgress: { _ in })
            #expect(WhisperBackend.isEncoderInstalled(modelId: fixture.model.id) == false)
        }
    }

    @Test func installIfNeededInstallsFromZip() async throws -> Void {
        let fixture = try WhisperDownloadFixture(encoder: WhisperDownloadFixture.validEncoder)
        try await fixture.withSession { session in
            try await WhisperEncoderInstaller.installIfNeeded(model: fixture.model, session: session, onProgress: { _ in })
            #expect(WhisperBackend.isEncoderInstalled(modelId: fixture.model.id) == true)
        }
    }

    @Test func installIfNeededThrowsWhenMlmodelcMissingInZip() async throws -> Void {
        let fixture = try WhisperDownloadFixture(encoder: .init(ZIPFixture.encoderBundle(named: "wrong-name.mlmodelc")))
        try await fixture.withSession { session in
            await #expect(throws: ModelInstallationError.self) {
                try await WhisperEncoderInstaller.installIfNeeded(model: fixture.model, session: session, onProgress: { _ in })
            }
        }
    }

    @Test(arguments: [false, true])
    func installIfNeededRejectsInvalidEncoderBundle(directory: Bool) async throws -> Void {
        let name = WhisperDownloadFixture.encoderBundleName
        let entries: [ZIPFixture.Entry] =
            if directory == true { [.init(name: name + "/", mode: 0o040755), .init(name: name + "/model.mil")] }
            else { [.init(name: name, data: Data("file".utf8))] }
        let fixture = try WhisperDownloadFixture(encoder: .init(ZIPFixture.archive(entries)))
        try FileManager.default.createDirectory(at: fixture.encoderURL, withIntermediateDirectories: true)
        let original = fixture.encoderURL.appendingPathComponent("original")
        try Data().write(to: original)
        try await fixture.withSession { session in
            await #expect(throws: ModelInstallationError.self) {
                try await WhisperEncoderInstaller.installIfNeeded(model: fixture.model, session: session, onProgress: { _ in })
            }
            #expect(try Data(contentsOf: original).isEmpty == true)
            #expect(WhisperBackend.isEncoderInstalled(modelId: fixture.model.id) == false)
            let contents = try FileManager.default.contentsOfDirectory(atPath: fixture.encoderURL.deletingLastPathComponent().path)
            #expect(contents.contains(where: { $0.contains(".staging-") }) == false)
        }
    }

    @Test func installIfNeededCompletesWhenZipSizeNil() async throws -> Void {
        let fixture = try WhisperDownloadFixture(encoder: .init(WhisperDownloadFixture.validEncoder.data, size: nil))
        try await fixture.withSession { session in
            try await WhisperEncoderInstaller.installIfNeeded(model: fixture.model, session: session, onProgress: { _ in })
            #expect(WhisperBackend.isEncoderInstalled(modelId: fixture.model.id) == true)
        }
    }

    @Test(arguments: [false, true])
    func corruptArchiveIsRejectedAfterCompleteDownload(forceInvalidStderr: Bool) async throws -> Void {
        SuperscribeKitTestHooks.forceUnzipInvalidStderr = forceInvalidStderr
        let fixture = try WhisperDownloadFixture(encoder: .init(Data("not-a-zip".utf8)))
        try await fixture.withSession { session in
            do {
                try await WhisperEncoderInstaller.installIfNeeded(model: fixture.model, session: session, onProgress: { _ in })
                Issue.record("Expected corrupt archive rejection")
            }
            catch ModelInstallationError.installFailed {
                #expect(WhisperBackend.isEncoderInstalled(modelId: fixture.model.id) == false)
            }
        }
    }

    @Test func decodeUnzipStderrUsesUTF8Payload() -> Void {
        #expect(WhisperEncoderInstaller.decodeUnzipStderr(raw: Data("bad zip".utf8)) == "bad zip")
    }

    @Test func decodeUnzipStderrUsesFallbackForInvalidUTF8() -> Void {
        SuperscribeKitTestHooks.forceUnzipInvalidStderr = true
        #expect(WhisperEncoderInstaller.decodeUnzipStderr(raw: Data("ignored".utf8)) == "unzip failed")
    }

    @Test func decodeUnzipStderrFallsBackWhenRawUTF8Invalid() -> Void {
        #expect(WhisperEncoderInstaller.decodeUnzipStderr(raw: Data([0xFF, 0xFE])) == "unzip failed")
    }

    @Test func installIfNeededMissingBundleWhenEnumeratorForcedNil() async throws -> Void {
        SuperscribeKitTestHooks.forceEncoderBundleEnumeratorNil = true
        let fixture = try WhisperDownloadFixture(encoder: WhisperDownloadFixture.validEncoder)
        try await fixture.withSession { session in
            await #expect(throws: ModelInstallationError.self) {
                try await WhisperEncoderInstaller.installIfNeeded(model: fixture.model, session: session, onProgress: { _ in })
            }
        }
    }
}
