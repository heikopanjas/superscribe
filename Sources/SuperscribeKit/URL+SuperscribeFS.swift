import Foundation

/// How to resolve a collision when promoting a staged path to its final location.
public enum AtomicReplacePolicy: Sendable {
    /// If `final` already exists, delete `staging` and leave `final` untouched.
    case discardStagingIfFinalExists
    /// Remove `final` when present, then move `staging` into place.
    case removeFinalThenMove
}

public enum SuperscribeFS {
    public static func isExistingDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) == true
            && isDir.boolValue == true
    }

    public static func isExistingFile(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) == true
            && isDir.boolValue == false
    }

    /// Returns a sibling staging path: `<parent>/<basename>.staging-<uuid>`.
    public static func stagingURL(beside sibling: URL, label: String? = nil) -> URL {
        let parent = sibling.deletingLastPathComponent()
        let base = label ?? sibling.lastPathComponent
        return parent.appendingPathComponent("\(base).staging-\(UUID().uuidString)")
    }

    /// Promotes `staging` to `final` according to `policy`.
    public static func atomicReplace(
        staging: URL,
        final: URL,
        policy: AtomicReplacePolicy
    ) throws {
        switch policy {
            case .discardStagingIfFinalExists:
                if FileManager.default.fileExists(atPath: final.path) == true {
                    try? FileManager.default.removeItem(at: staging)
                    return
                }
                try FileManager.default.moveItem(at: staging, to: final)
            case .removeFinalThenMove:
                if FileManager.default.fileExists(atPath: final.path) == true {
                    try FileManager.default.removeItem(at: final)
                }
                try FileManager.default.moveItem(at: staging, to: final)
        }
    }

    /// `true` when `directory` contains at least one `.mlmodelc` entry.
    public static func containsCompiledCoreMLBundle(at directory: URL) -> Bool {
        guard isExistingDirectory(at: directory) == true else { return false }
        let contents: [String] =
            (try? {
                if SuperscribeKitTestHooks.forceContentsOfDirectoryFailure == true {
                    throw NSError(domain: "SuperscribeFS", code: 1)
                }
                return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            }()) ?? []
        return contents.contains(where: { $0.hasSuffix(".mlmodelc") }) == true
    }
}
