import Darwin
import Foundation

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
    ) throws -> Void {
        let flags: UInt32 = policy == .discardStagingIfFinalExists ? UInt32(RENAME_EXCL) : UInt32(RENAME_SWAP)
        if renamex_np(staging.path, final.path, flags) == 0 {
            if policy == .replaceExisting {
                try? FileManager.default.removeItem(at: staging)
            }
            return
        }
        let failure = errno
        if policy == .discardStagingIfFinalExists, failure == EEXIST {
            try? FileManager.default.removeItem(at: staging)
            return
        }
        if policy == .replaceExisting, failure == ENOENT {
            if renamex_np(staging.path, final.path, UInt32(RENAME_EXCL)) == 0 { return }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
    }

    /// `true` when `directory` contains at least one `.mlmodelc` entry.
    public static func containsCompiledCoreMLBundle(at directory: URL) -> Bool {
        guard Self.isExistingDirectory(at: directory) == true else { return false }
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
