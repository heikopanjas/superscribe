import AVFoundation
import Foundation

/// Errors raised by `AudioPreparer`.
public enum AudioPreparerError: Error, CustomStringConvertible {
    case cannotReadFile(URL, underlying: Error)
    case unsupportedFormat(URL)
    case conversionFailed(String)

    public var description: String {
        switch self {
            case .cannotReadFile(let url, let err):
                return "Cannot read audio/video file \(url.path): \(err)"
            case .unsupportedFormat(let url):
                return "Unsupported media format: \(url.path)"
            case .conversionFailed(let msg):
                return "Audio conversion failed: \(msg)"
        }
    }
}
