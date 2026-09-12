import AVFoundation
import Foundation
import Speech

enum AppleSpeechError: Error, LocalizedError, Sendable {
    case runtimeUnavailable
    case localeUnsupported(String)
    case localeInstallFailed(underlying: any Error)
    case transcriptionFailed
    case audioConversionFailed
    case allocationLimitReached

    var errorDescription: String? {
        switch self {
            case .runtimeUnavailable:
                return AppleSpeechSupport.unavailableMessage()
            case .localeUnsupported(let id):
                return "Locale '\(id)' is not supported by Apple Speech"
            case .localeInstallFailed(let underlying):
                return "Apple Speech locale install failed: \(underlying)"
            case .transcriptionFailed:
                return "Apple Speech transcription failed"
            case .audioConversionFailed:
                return "Apple Speech audio conversion failed"
            case .allocationLimitReached:
                return """
                    Apple Speech locale limit reached; deallocate an unused locale with \
                    'superscribe model --rm <locale> --backend appleSpeech'
                    """
        }
    }
}
