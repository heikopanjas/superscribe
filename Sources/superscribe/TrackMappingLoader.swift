import Foundation
import SuperscribeKit

internal enum TrackMappingLoader {
    internal static func load(from file: URL, relativeTo directory: URL) throws -> [TrackInput] {
        let mapping = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        let tracks = mapping.sorted { $0.key < $1.key }.map { speaker, filename in
            let url = filename.hasPrefix("/") ? URL(fileURLWithPath: filename) : directory.appendingPathComponent(filename)
            return TrackInput(speaker: speaker, file: url)
        }
        try TrackInput.validate(tracks)
        return tracks
    }
}
