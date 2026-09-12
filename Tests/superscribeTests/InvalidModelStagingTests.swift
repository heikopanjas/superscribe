import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Invalid staged installation", .serialized, ResetSharedStateTrait())
struct InvalidModelStagingTests {
    @Test func validatesStagingBeforeReplacingIncompleteInstall() async throws -> Void {
        let destination = try ModelInstaller.installPath(for: "v3", backend: .parakeet)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let original = destination.appendingPathComponent("original")
        try Data([42]).write(to: original)
        try await MockURLSessionHelpers.withMockHandler(
            { request in
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                if url.path.contains("/api/") == true {
                    return (response, Data("{\"id\":\"FluidInference/parakeet-tdt-0.6b-v3-coreml\",\"siblings\":[{\"rfilename\":\"README.md\",\"size\":1}]}".utf8))
                }
                return (response, Data([1]))
            },
            { session in
                let model = RemoteModelInfo(id: "v3", repoId: try ParakeetBackend.huggingFaceRepoId(for: "v3"), repoURL: URL(fileURLWithPath: "/unused"))
                await #expect(throws: ModelInstallationError.self) { _ = try await ModelInstaller.install(model: model, backend: .parakeet, session: session) }
                #expect(try Data(contentsOf: original) == Data([42]))
                let contents = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
                #expect(contents.contains(where: { $0.contains("staging") }) == false)
            })
    }
}
