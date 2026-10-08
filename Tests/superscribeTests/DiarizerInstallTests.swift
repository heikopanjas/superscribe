import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Diarizer installation", .serialized, ResetSharedStateTrait())
struct DiarizerInstallTests {
    private static let bundleFiles = [
        "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/coremldata.bin", "monolithic/v2/Nemotron3Diarizer_fast128.mlmodelc/weights/weight.bin"
    ]

    private static func payload(_ files: [String], size: Int? = 3) throws -> Data {
        let siblings = files.map { name -> [String: Any] in
            if let size { return ["rfilename": name, "size": size] }
            return ["rfilename": name, "size": NSNull()]
        }
        return try JSONSerialization.data(withJSONObject: ["id": DiarizerModel.repoId, "siblings": siblings])
    }

    private static func handler(payload: Data, failing: String? = nil) -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        return { request in
            let url = try #require(request.url)
            if url.absoluteString.contains("/api/models/\(DiarizerModel.repoId)") == true {
                return (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), payload)
            }
            if let failing {
                if url.absoluteString.hasSuffix(failing) == true {
                    return (try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)), Data())
                }
            }
            return (try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data("bin".utf8))
        }
    }

    private static func stagingLeftovers() throws -> [String] {
        let parent = try DiarizerModel.installPath().deletingLastPathComponent()
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        return entries.filter { $0.contains(".staging-") }
    }

    @Test func installsSelectedFilesWithMarkerAndNoBackend() async throws -> Void {
        let payload = try Self.payload(Self.bundleFiles + ["monolithic/v2/Nemotron3Diarizer_fast32.mlmodelc/coremldata.bin", "learnable_sil_emb.bin"])
        let backends = BackendRecorder()
        let path = try await MockURLSessionHelpers.withMockHandler(Self.handler(payload: payload)) { session in
            return try await ModelInstaller.installDiarizer(session: session, onProgress: { backends.record($0.backend) })
        }
        #expect(path.path == (try DiarizerModel.installPath()).path)
        #expect(DiarizerModel.isInstalled(at: path) == true)
        #expect(FileManager.default.fileExists(atPath: path.appendingPathComponent("Nemotron3Diarizer_fast32.mlmodelc").path) == false)
        #expect(backends.values.isEmpty == false)
        #expect(backends.values.allSatisfy { $0 == nil } == true)
    }

    @Test func installedModelSkipsTheNetwork() async throws -> Void {
        let path = try DiarizerModel.installPath()
        try TestHelpers.makeDiarizerInstallation(at: path)
        let installed = try await MockURLSessionHelpers.withMockHandler(
            { request in
                Issue.record("Unexpected request \(String(describing: request.url))")
                throw URLError(.unsupportedURL)
            },
            { session in
                return try await ModelInstaller.installDiarizer(session: session)
            })
        #expect(installed.path == path.path)
    }

    @Test func staleWeightsAreReplacedAndUnknownSizesAreAccepted() async throws -> Void {
        let path = try DiarizerModel.installPath()
        try TestHelpers.makeDiarizerInstallation(at: path)
        try Data("older".utf8).write(to: path.appendingPathComponent(DiarizerModel.weightsMarker))
        let payload = try Self.payload(Self.bundleFiles + ["learnable_sil_emb.bin"], size: nil)
        _ = try await MockURLSessionHelpers.withMockHandler(Self.handler(payload: payload)) { session in
            return try await ModelInstaller.installDiarizer(session: session)
        }
        #expect(DiarizerModel.isInstalled(at: path) == true)
    }

    @Test func failedDownloadLeavesNothingBehind() async throws -> Void {
        let payload = try Self.payload(Self.bundleFiles + ["learnable_sil_emb.bin"])
        await #expect(throws: (any Error).self) {
            try await MockURLSessionHelpers.withMockHandler(Self.handler(payload: payload, failing: "learnable_sil_emb.bin")) { session in
                _ = try await ModelInstaller.installDiarizer(session: session)
            }
        }
        #expect(FileManager.default.fileExists(atPath: try DiarizerModel.installPath().path) == false)
        #expect(try Self.stagingLeftovers().isEmpty == true)
    }

    @Test func incompleteRepositoryFailsValidation() async throws -> Void {
        let payload = try Self.payload(Self.bundleFiles)
        await #expect(throws: ModelInstallationError.self) {
            try await MockURLSessionHelpers.withMockHandler(Self.handler(payload: payload)) { session in
                _ = try await ModelInstaller.installDiarizer(session: session)
            }
        }
        #expect(try Self.stagingLeftovers().isEmpty == true)
    }

    @Test func removalReportsWhetherAnythingWasInstalled() async throws -> Void {
        #expect(try await ModelInstaller.removeDiarizer() == false)
        let path = try DiarizerModel.installPath()
        try TestHelpers.makeDiarizerInstallation(at: path)
        #expect(try await ModelInstaller.removeDiarizer() == true)
        #expect(FileManager.default.fileExists(atPath: path.path) == false)
    }
}
