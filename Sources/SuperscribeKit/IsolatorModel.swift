import DemucsMLX
import Foundation

/// Supported local vocal-isolation models, independent of the ASR backend.
public enum IsolatorModel: String, Codable, CaseIterable, Sendable {
    case htdemucs
    case htdemucsFT = "htdemucs_ft"

    public func installPath() throws -> URL {
        return try ModelPathValidation.resolve(self.rawValue, under: SuperscribePaths.isolatorModelsDirectory())
    }

    internal var receiptURL: URL {
        return UserConfig.configFileURL.deletingLastPathComponent().appendingPathComponent("isolator-\(self.rawValue).json")
    }

    internal var demucsModel: DemucsModel {
        switch self {
            case .htdemucs: return .htdemucs
            case .htdemucsFT: return .htdemucsFT
        }
    }

    internal var separationOptions: SeparationOptions {
        var options = SeparationOptions()
        options.seed = 0
        options.cacheValidation = .verifiedIdentity
        if self == .htdemucsFT { options.stem = "vocals" }
        return options
    }
}
