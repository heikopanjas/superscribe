import AVFoundation
import Foundation

/// Errors raised by `Analyzer`.
public enum AnalyzerError: Error, CustomStringConvertible {
    case unsupportedFormat(URL)
    case readFailed(URL, underlying: Error)

    public var description: String {
        switch self {
            case .unsupportedFormat(let url):
                return "Unsupported audio format: \(url.path)"
            case .readFailed(let url, let underlying):
                return "Failed to read audio file \(url.path): \(underlying)"
        }
    }
}
