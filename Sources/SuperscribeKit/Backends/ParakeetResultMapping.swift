import FluidAudio
import Foundation

extension AsrManager: ParakeetASRSession {}

/// Maps FluidAudio ASR output to superscribe segment transcriptions.
enum ParakeetResultMapping {
    static func map(
        _ asr: ASRResult,
        segment: SpeechSegment
    ) -> SegmentTranscription {
        let words: [TimedWord]

        if let timings = asr.tokenTimings, timings.isEmpty == false {
            words = Self.mergeTokensIntoWords(timings, segmentOffset: segment.start)
        }
        else {
            let text = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == true {
                words = []
            }
            else {
                words = [TimedWord(text: text, start: segment.start, end: segment.end)]
            }
        }

        return SegmentTranscription(segment: segment, words: words)
    }

    static func mergeTokensIntoWords(
        _ timings: [TokenTiming],
        segmentOffset: TimeInterval
    ) -> [TimedWord] {
        var accumulator = TokenAccumulator()
        for timing in timings {
            accumulator.accept(
                token: timing.token,
                start: timing.startTime,
                end: timing.endTime
            )
        }
        return accumulator.finish(segmentOffset: segmentOffset)
    }
}
