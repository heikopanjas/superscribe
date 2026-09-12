import Foundation

internal enum ModelInstallSupport {
    internal static func requireInstalled(at path: URL, modelId: String, backend: Backend) throws -> Void {
        let installed: Bool
        switch backend {
            case .parakeet:
                let descriptor = try ParakeetBackend.descriptor(for: modelId)
                installed = ModelArtifacts.parakeet(at: path, descriptor: descriptor)
            case .whisperCpp:
                installed = ModelArtifacts.nonemptyFile(at: path)
            case .appleSpeech:
                // Speech reservations use the asynchronous registry, never a filesystem marker.
                installed = false
        }
        guard installed == true else {
            throw ModelInstallationError.modelNotInstalled(model: modelId, backend: backend)
        }
    }
}
