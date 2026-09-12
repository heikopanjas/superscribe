import Foundation

internal enum ModelPathValidation {
    internal static func identifier(_ id: String) throws -> Void {
        guard id.range(of: "\\A[A-Za-z0-9][A-Za-z0-9._-]*\\z", options: .regularExpression) != nil else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
    }

    internal static func components(_ path: String) throws -> [String] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." && $0.contains("\\") == false && $0.rangeOfCharacter(from: .controlCharacters) == nil }) == true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return parts
    }

    internal static func resolve(_ path: String, under root: URL) throws -> URL {
        let parts = try Self.components(path)
        let destination = parts.reduce(root) { $0.appendingPathComponent($1) }
        let boundary = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let resolved = parts.reduce(root.standardizedFileURL.resolvingSymlinksInPath()) { partial, part in
            return partial.appendingPathComponent(part).resolvingSymlinksInPath()
        }.pathComponents
        guard resolved.starts(with: boundary) == true, resolved.count > boundary.count else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return destination
    }

    internal static func downloadURL(repoId: String, filename: String) throws -> URL {
        let repo = try Self.components(repoId)
        let file = try Self.components(filename)
        return try HTTPURL.make(host: "huggingface.co", path: "/" + (repo + ["resolve", "main"] + file).joined(separator: "/"))
    }
}
