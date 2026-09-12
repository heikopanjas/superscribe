import Foundation

internal enum SubtitleText {
    internal static func escape(_ text: String) -> String {
        return text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Counts visible Swift characters, excluding injected timestamp or voice markup.
    internal static func wrap(_ words: [TimedWord], maximum: Int?, transform: (Int, String) -> String) -> String {
        var output = ""
        var length = 0
        for (index, word) in words.enumerated() {
            let parts = word.text.split(whereSeparator: \.isWhitespace)
            for (partIndex, part) in parts.enumerated() {
                let text = String(part)
                if length > 0 {
                    if let maximum, length + 1 + text.count > maximum {
                        output += "\n"
                        length = 0
                    }
                    else {
                        output += " "
                        length += 1
                    }
                }
                output += transform(partIndex == 0 ? index : -1, text)
                length += text.count
            }
        }
        return output
    }
}
