import Foundation

/// One repository file and its staging-relative destination.
internal struct ModelDownloadFile: Sendable {
    internal let rfilename: String
    internal let relativePath: String
    internal let expectedSize: Int64?

    /// Sum of the expected sizes, or `nil` when the selection is empty or any size is unknown.
    internal static func totalSize(of files: [ModelDownloadFile]) -> Int64? {
        let sizes = files.compactMap(\.expectedSize)
        guard sizes.isEmpty == false, sizes.count == files.count else { return nil }
        return sizes.reduce(0, +)
    }

    /// Selects the root-level `files` by exact path plus the contents of each `prefix + bundle` directory,
    /// with `prefix` stripped so bundles install beside the root files.
    internal static func select(from siblings: [HuggingFaceHub.HFSibling], bundles: Set<String>, files: Set<String>, under prefix: String = "") -> [ModelDownloadFile] {
        return siblings.compactMap { sibling in
            if files.contains(sibling.rfilename) == true {
                return ModelDownloadFile(rfilename: sibling.rfilename, relativePath: sibling.rfilename, expectedSize: sibling.size)
            }
            guard sibling.rfilename.hasPrefix(prefix) == true else { return nil }
            let relativePath = String(sibling.rfilename.dropFirst(prefix.count))
            let components = relativePath.split(separator: "/", maxSplits: 1)
            guard components.count == 2, bundles.contains(String(components[0])) == true else { return nil }
            return ModelDownloadFile(rfilename: sibling.rfilename, relativePath: relativePath, expectedSize: sibling.size)
        }
    }
}
