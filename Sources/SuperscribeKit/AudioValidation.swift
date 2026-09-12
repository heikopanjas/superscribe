import AVFoundation

internal enum AudioValidation {
    internal static func validate(_ format: AudioFormat) throws -> Void {
        guard format.sampleRate > 0, format.channels == 1 else {
            throw AudioPreparerError.conversionFailed("A positive sample rate and mono output are required")
        }
    }

    internal static func sampleRate(_ rate: Double) throws -> Int {
        guard let value = Int(exactly: rate), value > 0 else {
            throw AudioPreparerError.conversionFailed("A positive integral sample rate is required")
        }
        return value
    }

    internal static func frameCount(_ value: Double) throws -> AVAudioFrameCount {
        guard value.isFinite == true, value >= 0, value <= Double(AVAudioFrameCount.max) else {
            throw AudioPreparerError.conversionFailed("Audio frame count exceeds the supported range")
        }
        return AVAudioFrameCount(value)
    }

    internal static func sliceRange(segment: SpeechSegment, sampleRate: Int, count: Int) throws -> Range<Int> {
        guard segment.start.isFinite == true, segment.end.isFinite == true, segment.end >= segment.start, sampleRate > 0 else {
            throw AudioPreparerError.conversionFailed("Invalid audio interval or sample rate")
        }
        let lower = min(Double(count), max(0, segment.start * Double(sampleRate)))
        let upper = min(Double(count), max(0, segment.end * Double(sampleRate)))
        return Int(lower) ..< Int(upper)
    }
}
