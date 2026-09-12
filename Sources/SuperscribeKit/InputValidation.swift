import Foundation

extension AnalyzerConfig {
    public func validate() throws -> Void {
        guard self.silenceThresholdDB.isFinite == true,
            self.minSilenceDuration.isFinite == true, self.minSilenceDuration >= 0,
            self.padding.isFinite == true, self.padding >= 0,
            self.minSegmentDuration.isFinite == true, self.minSegmentDuration >= 0,
            self.windowSize > 0
        else { throw InputValidationError("Analyzer values must be finite, durations nonnegative, and window size positive") }
    }
}

extension TrackInput {
    public func validate() throws -> Void {
        guard self.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw InputValidationError("Speaker names must not be blank") }
        let values = try self.file.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
        guard values.isRegularFile == true, values.isReadable == true else { throw InputValidationError("Track must be a readable regular file: \(self.file.path)") }
    }

    public static func validate(_ tracks: [TrackInput]) throws -> Void {
        guard tracks.isEmpty == false else { throw InputValidationError("At least one track is required") }
        for track in tracks { try track.validate() }
    }
}
