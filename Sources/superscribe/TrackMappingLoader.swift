import Foundation
import SuperscribeKit

internal enum TrackMappingLoader {
    internal static func load(from file: URL, relativeTo directory: URL) throws -> [TrackInput] {
        let mapping = try JSONDecoder().decode([String: TrackMappingEntry].self, from: Data(contentsOf: file))
        let tracks = mapping.sorted { $0.key < $1.key }.map { speaker, entry in
            let url = entry.file.hasPrefix("/") ? URL(fileURLWithPath: entry.file) : directory.appendingPathComponent(entry.file)
            return TrackInput(speaker: speaker, file: url, diarization: entry.diarization)
        }
        try TrackInput.validate(tracks)
        return tracks
    }
}
