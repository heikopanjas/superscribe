import AVFoundation
import Foundation
import Speech

/// Availability-gated transcriber construction; lives in the excluded LiveAPI shim.
enum AppleSpeechTranscriberBridge {
    static func make(model: String) throws -> any Transcriber {
        if #available(macOS 26, *) {
            guard AppleSpeechBackend.isAvailable == true else {
                throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
            }
            return try AppleSpeechBackend(model: model)
        }
        throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
    }
}
