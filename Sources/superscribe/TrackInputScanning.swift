import ArgumentParser
import Foundation
import SuperscribeKit

/// Scans a directory for audio track files and builds speaker-keyed mappings.
enum TrackInputScanning {
    static let audioExtensions: Set<String> = [
        "mp3", "wav", "m4a", "aac", "flac", "ogg", "mp4", "mov", "caf", "opus"
    ]

    /// Returns audio file URLs in a directory, sorted by localized filename.
    static func scanAudioFiles(in directory: URL) throws -> [URL] {
        guard SuperscribeFS.isExistingDirectory(at: directory) == true else {
            throw ValidationError("\(directory.path): not a directory.")
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        )
        return
            contents
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }
    }

    /// Maps sorted audio files to `speaker-<n>` keys with cwd-relative paths.
    static func makeTrackMap(from audioFiles: [URL], relativeTo cwdURL: URL) -> [String: String] {
        let cwdPath = cwdURL.standardizedFileURL.path + "/"
        var tracks: [String: String] = [:]
        for (i, url) in audioFiles.enumerated() {
            let absPath = url.standardizedFileURL.path
            let relPath =
                absPath.hasPrefix(cwdPath)
                ? String(absPath.dropFirst(cwdPath.count))
                : absPath
            tracks["speaker-\(i + 1)"] = relPath
        }
        return tracks
    }

    /// Scans a directory and returns a speaker-keyed track map.
    static func scanTracks(in directory: URL, relativeTo cwdURL: URL) throws -> [String: String] {
        let audioFiles = try scanAudioFiles(in: directory)
        guard audioFiles.isEmpty == false else {
            throw ValidationError("No audio files found in \(directory.path).")
        }
        return makeTrackMap(from: audioFiles, relativeTo: cwdURL)
    }
}
