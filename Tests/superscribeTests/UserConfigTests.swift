import Foundation
import Testing

@testable import SuperscribeKit

@Suite("UserConfig", .serialized, ResetSharedStateTrait())
struct UserConfigTests {

    @Test func loadMissingFileReturnsDefaults() throws {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("missing-config.json")
            UserConfig.$taskOverrideConfigFileURL.withValue(url) {
                let loaded = UserConfig.load()
                #expect(loaded.defaultModels.isEmpty == true)
                #expect(loaded.defaultBackend == nil)
            }
        }
    }

    @Test func staticOverrideConfigFileURL() throws {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig-static") { dir in
            let url = dir.appendingPathComponent("static-config.json")
            let prior = UserConfig.overrideConfigFileURL
            UserConfig.overrideConfigFileURL = url
            defer { UserConfig.overrideConfigFileURL = prior }
            #expect(UserConfig.configFileURL.path == url.path)
        }
    }

    @Test func saveLoadRoundTripAndMutators() throws {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("config.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try UserConfig.$taskOverrideConfigFileURL.withValue(url) {
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
    }

    @Test func resolvedDefaultBackendIgnoresInvalidRawValue() throws {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("config.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try UserConfig.$taskOverrideConfigFileURL.withValue(url) {
                var cfg = UserConfig()
                cfg.defaultBackend = "not-a-real-backend"
                try cfg.save()

                let loaded = UserConfig.load()
                #expect(loaded.resolvedDefaultBackend() == .parakeet)
            }
        }
    }
}
