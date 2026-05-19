import Foundation
import Testing

@testable import SuperscribeKit

@Suite("UserConfig", .serialized)
struct UserConfigTests {

    @Test func loadMissingFileReturnsDefaults() throws {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("missing-config.json")
            UserConfig.overrideConfigFileURL = url
            defer { UserConfig.overrideConfigFileURL = nil }

            let loaded = UserConfig.load()
            #expect(loaded.defaultModels.isEmpty == true)
            #expect(loaded.defaultBackend == nil)
        }
    }

    @Test func saveLoadRoundTripAndMutators() throws {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("config.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            UserConfig.overrideConfigFileURL = url
            defer { UserConfig.overrideConfigFileURL = nil }

            var cfg = UserConfig()
            cfg.setDefaultModel("large-v3-turbo", for: .whisperCpp)
            cfg.setDefaultBackend(.whisperCpp)
            try cfg.save()

            let loaded = UserConfig.load()
            #expect(loaded.defaultModel(for: .whisperCpp) == "large-v3-turbo")
            #expect(loaded.resolvedDefaultBackend() == .whisperCpp)
            #expect(loaded.defaultBackend == Backend.whisperCpp.rawValue)
        }
    }

    @Test func resolvedDefaultBackendIgnoresInvalidRawValue() throws {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("config.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            UserConfig.overrideConfigFileURL = url
            defer { UserConfig.overrideConfigFileURL = nil }

            var cfg = UserConfig()
            cfg.defaultBackend = "not-a-real-backend"
            try cfg.save()

            let loaded = UserConfig.load()
            #expect(loaded.resolvedDefaultBackend() == .parakeet)
        }
    }
}
