import ArgumentParser
import Foundation
import SuperscribeKit

/// Parses a `name=path` track specification into its components.
struct TrackSpec: ExpressibleByArgument {
    let speaker: String
    let path: String

    init?(argument: String) {
        guard let separator = argument.firstIndex(of: "=") else { return nil }
        let speaker = String(argument[..<separator]).trimmingCharacters(in: .whitespaces)
        let path = String(argument[argument.index(after: separator)...]).trimmingCharacters(
            in: .whitespaces)
        guard speaker.isEmpty == false, path.isEmpty == false else { return nil }
        self.speaker = speaker
        self.path = path
    }
}
