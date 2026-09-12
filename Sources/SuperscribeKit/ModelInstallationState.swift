import Foundation

public enum ModelInstallationState: String, Codable, Sendable {
    case installed
    case reserved
    case installedAndReserved

    public var hasInstalledAssets: Bool { return self != .reserved }
    public var hasReservation: Bool { return self != .installed }
}
