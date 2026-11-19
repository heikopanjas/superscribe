import Foundation
import Testing

@testable import SuperscribeKit

/// Repository metadata and exact download routes, scoped by the existing mock-session lifecycle.
struct WhisperDownloadFixture: Sendable {
    struct Artifact: Sendable {
        let data: Data
        let size: Int64?
        let status: Int

        init(_ data: Data, status: Int = 200) {
            self.init(data, size: Int64(data.count), status: status)
        }

        init(_ data: Data, size: Int64?, status: Int = 200) {
            self.data = data
            self.size = size
            self.status = status
        }
    }

    private static let modelId = "fixture"
    let model: RemoteModelInfo
    private let metadata: Data
    private let metadataStatus: Int
    private let downloads: [String: Artifact]

    static var encoderBundleName: String {
        return WhisperBackend.encoderInstallPath(for: Self.modelId).lastPathComponent
    }

    static var validEncoder: Artifact {
        return Artifact(ZIPFixture.encoderBundle(named: Self.encoderBundleName))
    }

    var binaryURL: URL { return WhisperBackend.installPath(for: self.model.id) }
    var encoderURL: URL { return WhisperBackend.encoderInstallPath(for: self.model.id) }

    init(binary: Artifact? = nil, encoder: Artifact? = nil, catalogSize: Int64? = nil, metadataStatus: Int = 200) throws {
        let repo = WhisperBackend.huggingFaceRepoId
        let artifacts = [
            ("ggml-\(Self.modelId).bin", binary),
            (WhisperBackend.encoderZipRemoteName(for: Self.modelId), encoder)
        ].compactMap { name, artifact in artifact.map { (name, $0) } }
        let siblings = artifacts.map { name, artifact -> [String: Any] in
            return ["rfilename": name, "size": artifact.size.map { $0 as Any } ?? NSNull()]
        }
        self.metadata = try JSONSerialization.data(withJSONObject: ["id": repo, "lastModified": NSNull(), "siblings": siblings])
        self.metadataStatus = metadataStatus
        self.downloads = Dictionary(uniqueKeysWithValues: artifacts.map { ("/\(repo)/resolve/main/\($0.0)", $0.1) })
        self.model = RemoteModelInfo(
            id: Self.modelId, repoId: repo, totalSizeBytes: catalogSize ?? binary?.size, fileCount: artifacts.count,
            repoURL: try #require(URL(string: "https://huggingface.co/\(repo)")))
    }

    func response(to request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url, url.scheme == "https", url.host == "huggingface.co", request.httpMethod == "GET" else { throw URLError(.unsupportedURL) }
        let data: Data
        let status: Int
        if url.path == "/api/models/\(self.model.repoId)", url.query == "blobs=true" {
            data = self.metadata
            status = self.metadataStatus
        }
        else if url.query == nil, let artifact = self.downloads[url.path] {
            data = artifact.data
            status = artifact.status
        }
        else {
            throw URLError(.unsupportedURL)
        }
        return (try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)), data)
    }

    func withSession<Value>(_ body: (URLSession) async throws -> Value) async rethrows -> Value {
        return try await MockURLSessionHelpers.withMockHandler(
            { request in
                do { return try self.response(to: request) }
                catch {
                    Issue.record("Unexpected repository fixture request: \(request)")
                    throw error
                }
            }, body)
    }
}
