import Foundation
import SuperscribeKit

/// One `tracks.superscribe.json` value: a file path for an isolated track, or
/// `{ "file": …, "diarize": true, "speakers": [ … ] }` for a mixed recording.
struct TrackMappingEntry: Decodable {
    let file: String
    let diarization: TrackDiarization?

    private enum CodingKeys: String, CodingKey {
        case file
        case diarize
        case speakers
    }

    init(from decoder: any Decoder) throws {
        if let file = try? decoder.singleValueContainer().decode(String.self) {
            self.file = file
            self.diarization = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.file = try container.decode(String.self, forKey: .file)
        let speakers = try container.decodeIfPresent([String].self, forKey: .speakers)
        guard try container.decodeIfPresent(Bool.self, forKey: .diarize) == true else {
            if speakers != nil {
                throw DecodingError.dataCorruptedError(forKey: .speakers, in: container, debugDescription: "\"speakers\" requires \"diarize\": true")
            }
            self.diarization = nil
            return
        }
        self.diarization = TrackDiarization(speakerNames: speakers ?? [])
    }
}
