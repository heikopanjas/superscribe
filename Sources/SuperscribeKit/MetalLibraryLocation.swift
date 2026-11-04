import Darwin
import Foundation

/// Resolves shipped shaders before MLX can initialize its GPU runtime.
internal enum MetalLibraryLocation {
    internal static func resolve(executable: URL?, bundles: [URL]) throws -> URL {
        let roots = (executable.map { [$0.resolvingSymlinksInPath().deletingLastPathComponent()] } ?? []) + bundles
        for root in roots {
            for suffix in [
                "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", "mlx-swift_Cmlx.bundle/default.metallib",
                "mlx.metallib", "Resources/mlx.metallib"
            ] {
                let file = root.appendingPathComponent(suffix)
                var status = stat()
                if stat(file.path, &status) == 0,
                    status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), status.st_size > 0,
                    FileManager.default.isReadableFile(atPath: file.path) == true
                {
                    return URL(fileURLWithPath: file.path).standardizedFileURL
                }
            }
        }
        throw InputValidationError("Missing MLX Metal shaders. Install mlx-swift_Cmlx.bundle beside superscribe from the same release archive.")
    }
}
