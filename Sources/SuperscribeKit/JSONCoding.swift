import Foundation

/// Shared JSON encoder/decoder recipes for on-disk persistence.
public enum JSONCoding {
    /// Catalog, cache manifest, and CLI pretty-print output (ISO-8601 dates).
    public static func catalogEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func catalogDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// User config and track-mapping JSON (no dates).
    public static func configEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Intermediate transcript on-disk format (ISO-8601 dates, unescaped slashes).
    public static func transcriptEncoder() -> JSONEncoder {
        let encoder = catalogEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
