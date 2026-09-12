import Foundation

/// The system operations used by the covered locale lifecycle coordinator.
internal struct AppleSpeechAssetOperations: Sendable {
    internal var resolve: @Sendable (Locale) async -> Locale?
    internal var reserve: @Sendable (Locale) async throws -> Bool
    internal var release: @Sendable (Locale) async -> Void
    internal var installation: @Sendable (Locale) async throws -> AppleSpeechInstallation?
}
