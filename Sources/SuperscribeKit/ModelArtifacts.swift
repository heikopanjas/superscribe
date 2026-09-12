import Foundation

/// Lightweight artifact checks without loading a model or reaching a service.
internal enum ModelArtifacts {
    internal static func nonemptyFile(at url: URL, expectedSize: Int64? = nil) -> Bool {
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        guard let values = try? freshURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true, let size = values.fileSize, size > 0
        else { return false }
        return expectedSize == nil || Int64(size) == expectedSize
    }

    internal static func parakeet(at url: URL, descriptor: ParakeetBackend.ModelDescriptor) -> Bool {
        guard Self.nonemptyFile(at: url.appendingPathComponent(descriptor.vocabulary)) == true else { return false }
        return descriptor.bundles.allSatisfy { name in
            let bundle = url.appendingPathComponent(name)
            guard SuperscribeFS.isExistingDirectory(at: bundle) == true,
                let entries = try? FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            else { return false }
            return entries.contains { Self.nonemptyFile(at: $0) }
        }
    }
}
