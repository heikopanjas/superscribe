import Foundation
import Testing

@testable import SuperscribeKit

@Suite("UserConfig", .serialized, ResetSharedStateTrait())
struct UserConfigTests {

    @Test func loadMissingFileReturnsDefaults() throws -> Void {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("missing-config.json")
            try UserConfig.$taskOverrideConfigFileURL.withValue(url) {
                let loaded = try UserConfig.load()
                #expect(loaded.defaultModels.isEmpty == true)
                #expect(loaded.defaultBackend == nil)
                #expect(loaded.defaultIsolatorBackend == nil)
                #expect(loaded.defaultDiarizerBackend == nil)
                #expect(loaded.resolvedDefaultBackend() == .parakeet)
                #expect(loaded.resolvedDefaultIsolatorBackend() == .htdemucs)
                #expect(loaded.resolvedDefaultDiarizerBackend() == .nemotron)
            }
        }
    }

    @Test func staticOverrideConfigFileURL() throws -> Void {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig-static") { dir in
            let url = dir.appendingPathComponent("static-config.json")
            let prior = UserConfig.overrideConfigFileURL
            UserConfig.overrideConfigFileURL = url
            defer { UserConfig.overrideConfigFileURL = prior }
            #expect(UserConfig.configFileURL.path == url.path)
        }
    }

    @Test func saveLoadRoundTripAndMutators() throws -> Void {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("nested/config.json")
            try UserConfig.$taskOverrideConfigFileURL.withValue(url) {
                var cfg = UserConfig()
                cfg.setDefaultModel("large-v3-turbo", for: .whisperCpp)
                cfg.setDefaultBackend(.whisperCpp)
                cfg.setDefaultIsolatorBackend(.htdemucs)
                cfg.setDefaultDiarizerBackend(.nemotron)
                try cfg.save()

                let loaded = try UserConfig.load()
                #expect(loaded.defaultModel(for: .whisperCpp) == "large-v3-turbo")
                #expect(loaded.resolvedDefaultBackend() == .whisperCpp)
                #expect(loaded.defaultBackend == Backend.whisperCpp.rawValue)
                #expect(loaded.defaultIsolatorBackend == IsolatorBackend.htdemucs.rawValue)
                #expect(loaded.defaultDiarizerBackend == DiarizerBackend.nemotron.rawValue)
                #expect(loaded.resolvedDefaultIsolatorBackend() == .htdemucs)
                #expect(loaded.resolvedDefaultDiarizerBackend() == .nemotron)
            }
        }
    }

    @Test func resolvedDefaultBackendIgnoresInvalidRawValue() throws -> Void {
        try TestHelpers.withTempDirectory(prefix: "superscribe-userconfig") { dir in
            let url = dir.appendingPathComponent("config.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try UserConfig.$taskOverrideConfigFileURL.withValue(url) {
                var cfg = UserConfig()
                cfg.defaultBackend = "not-a-real-backend"
                cfg.defaultIsolatorBackend = "not-an-isolator"
                cfg.defaultDiarizerBackend = "not-a-diarizer"
                try cfg.save()

                let loaded = try UserConfig.load()
                #expect(loaded.resolvedDefaultBackend() == .parakeet)
                #expect(loaded.resolvedDefaultIsolatorBackend() == .htdemucs)
                #expect(loaded.resolvedDefaultDiarizerBackend() == .nemotron)
            }
        }
    }

    @Test func legacyConfigurationWithoutAuxiliaryDefaultsStillLoads() throws -> Void {
        let data = Data(#"{"defaultModels":{"parakeet":"v2"},"defaultBackend":"whisper.cpp"}"#.utf8)
        let config = try JSONDecoder().decode(UserConfig.self, from: data)
        #expect(config.resolvedDefaultBackend() == .whisperCpp)
        #expect(config.defaultModel(for: .parakeet) == "v2")
        #expect(config.resolvedDefaultIsolatorBackend() == .htdemucs)
        #expect(config.resolvedDefaultDiarizerBackend() == .nemotron)
    }
}
