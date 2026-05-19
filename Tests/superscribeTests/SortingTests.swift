import Foundation
import Testing

@testable import SuperscribeKit

@Suite("sortedById")
struct SortingTests {
    @Test func installedModelsSortById() {
        let models = [
            InstalledModelInfo(id: "z", path: URL(fileURLWithPath: "/z"), sizeBytes: 1),
            InstalledModelInfo(id: "a", path: URL(fileURLWithPath: "/a"), sizeBytes: 1),
            InstalledModelInfo(id: "m", path: URL(fileURLWithPath: "/m"), sizeBytes: 1)
        ]
        #expect(models.sortedById().map(\.id) == ["a", "m", "z"])
    }

    @Test func remoteModelsSortById() {
        let models = [
            RemoteModelInfo(
                id: "large",
                repoId: "org/large",
                totalSizeBytes: 1,
                fileCount: 1,
                lastModified: nil,
                repoURL: URL(string: "https://huggingface.co/org/large")!
            ),
            RemoteModelInfo(
                id: "base",
                repoId: "org/base",
                totalSizeBytes: 1,
                fileCount: 1,
                lastModified: nil,
                repoURL: URL(string: "https://huggingface.co/org/base")!
            )
        ]
        #expect(models.sortedById().map(\.id) == ["base", "large"])
    }
}
