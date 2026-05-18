import Foundation

/// Errors raised by the model installation pipeline (downloader + installer)
/// and by backends that refuse to auto-download.
public enum ModelInstallationError: Error, CustomStringConvertible, Sendable {
    /// A backend was asked to load a model whose files are not present on disk.
    case modelNotInstalled(model: String, backend: Backend)
    /// The requested model id is not present in the catalog.
    case unknownModel(model: String, backend: Backend, available: [String])
    /// Free disk space (quota-aware) is insufficient for the download.
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64, path: URL)
    /// A file failed to download or write to disk.
    case downloadFailed(url: URL, underlying: any Error)
    /// HTTP error from a download.
    case httpError(status: Int, url: URL)
    /// Atomic move from staging to final directory failed.
    case installFailed(path: URL, underlying: any Error)

    public var description: String {
        switch self {
            case .modelNotInstalled(let model, let backend):
                return """
                    \(backend.displayLabel) model '\(model)' is not installed. \
                    Install it with: superscribe models --download \(model) --backend \(backend.rawValue)
                    """
            case .unknownModel(let model, let backend, let available):
                let list = available.isEmpty ? "(catalog empty)" : available.joined(separator: ", ")
                return """
                    Unknown model '\(model)' for backend '\(backend.rawValue)'. \
                    Available: \(list)
                    """
            case .insufficientDiskSpace(let need, let have, let path):
                return """
                    Insufficient disk space at \(path.path): need \(formatBytesShort(need)), \
                    have \(formatBytesShort(have)) (quota-aware free).
                    """
            case .downloadFailed(let url, let underlying):
                return "Download failed for \(url.absoluteString): \(underlying)"
            case .httpError(let status, let url):
                return "HTTP \(status) downloading \(url.absoluteString)"
            case .installFailed(let path, let underlying):
                return "Install failed at \(path.path): \(underlying)"
        }
    }
}

extension Backend {
    /// Human-readable label for use in error messages.
    public var displayLabel: String {
        switch self {
            case .parakeet: return "Parakeet"
            case .whisperCpp: return "Whisper"
            case .appleSpeech: return "Apple Speech"
        }
    }
}

/// Compact byte formatter used in error messages (avoids importing the CLI helper).
private func formatBytesShort(_ bytes: Int64) -> String {
    let v = Double(bytes)
    if v >= 1_073_741_824 { return String(format: "%.1f GiB", v / 1_073_741_824) }
    if v >= 1_048_576 { return String(format: "%.1f MiB", v / 1_048_576) }
    if v >= 1_024 { return String(format: "%.1f KiB", v / 1_024) }
    return "\(bytes) B"
}
