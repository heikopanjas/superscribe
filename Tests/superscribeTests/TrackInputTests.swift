import Foundation
import Testing

@testable import superscribe

@Suite("TrackInputScanning", .serialized, ResetSharedStateTrait())
struct TrackInputTests {
    @Test func filtersByAudioExtension() throws {
        try TestHelpers.withTempDirectory { dir in
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("a.wav").path, contents: Data()
            )
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("b.txt").path, contents: Data()
            )
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("c.MP3").path, contents: Data()
            )

            let files = try TrackInputScanning.scanAudioFiles(in: dir)
            #expect(files.map(\.lastPathComponent) == ["a.wav", "c.MP3"])
        }
    }

    @Test func sortsByLocalizedFilename() throws {
        try TestHelpers.withTempDirectory { dir in
            for name in ["zeta.wav", "Alpha.wav", "beta.wav"] {
                FileManager.default.createFile(
                    atPath: dir.appendingPathComponent(name).path, contents: Data()
                )
            }

            let files = try TrackInputScanning.scanAudioFiles(in: dir)
            #expect(files.map(\.lastPathComponent) == ["Alpha.wav", "beta.wav", "zeta.wav"])
        }
    }

    @Test func speakerKeysAreOneBased() throws {
        try TestHelpers.withTempDirectory { dir in
            for name in ["first.wav", "second.wav"] {
                FileManager.default.createFile(
                    atPath: dir.appendingPathComponent(name).path, contents: Data()
                )
            }
            let files = try TrackInputScanning.scanAudioFiles(in: dir)
            let map = TrackInputScanning.makeTrackMap(from: files, relativeTo: dir)
            #expect(map == ["speaker-1": "first.wav", "speaker-2": "second.wav"])
        }
    }

    @Test func scanTracksThrowsWhenNoAudioFiles() throws {
        try TestHelpers.withTempDirectory { dir in
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("notes.txt").path, contents: Data()
            )
            #expect(throws: (any Error).self) {
                _ = try TrackInputScanning.scanTracks(in: dir, relativeTo: dir)
            }
        }
    }

    @Test func scanTracksReturnsSpeakerMap() throws {
        try TestHelpers.withTempDirectory { dir in
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("track.wav").path, contents: Data()
            )
            let map = try TrackInputScanning.scanTracks(in: dir, relativeTo: dir)
            #expect(map == ["speaker-1": "track.wav"])
        }
    }
}
