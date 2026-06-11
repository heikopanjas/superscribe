import AVFoundation
import Foundation
import Speech

/// Speech framework calls and stub/live branching isolated from unit-test coverage
/// (live paths require macOS 26+ and installed locale assets).
@available(macOS 26, *)
enum AppleSpeechLiveAPI {
    nonisolated(unsafe) internal static var testSupportedLocaleIds: [String]?
    nonisolated(unsafe) internal static var testInstalledLocaleIds: [String]?
    nonisolated(unsafe) internal static var testTranscriptionSpans: [AppleSpeechResultMapping.WordSpan]?
    nonisolated(unsafe) internal static var testForceInstallFailure = false
    nonisolated(unsafe) internal static var testForceTranscriptionFailure = false
    nonisolated(unsafe) internal static var testSkipLiveTranscription = false
    nonisolated(unsafe) internal static var testForceReserveFailure = false
    nonisolated(unsafe) internal static var testForceUnsupportedLocale = false
    nonisolated(unsafe) internal static var testSkipLocaleInstall = false

    static func supportedLocaleIds() async -> [String] {
        if let testSupportedLocaleIds { return testSupportedLocaleIds }
        let locales = await SpeechTranscriber.supportedLocales
        return locales.map { AppleSpeechSupport.normalizeLocaleId($0.identifier) }
    }

    static func installedLocaleIds() async -> [String] {
        if let testInstalledLocaleIds { return testInstalledLocaleIds }
        let locales = await SpeechTranscriber.installedLocales
        return locales.map { AppleSpeechSupport.normalizeLocaleId($0.identifier) }
    }

    static func isLocaleInstalled(_ localeId: String) async -> Bool {
        let normalized = AppleSpeechSupport.normalizeLocaleId(localeId)
        let installed = await installedLocaleIds()
        return installed.contains(where: { $0 == normalized })
    }

    static func resolveSupportedLocale(for locale: Locale) async -> Locale? {
        if testForceUnsupportedLocale == true { return nil }
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return equivalent
        }
        return nil
    }

    static func ensureLocaleInstalled(
        locale: Locale,
        modelId: String,
        backend: Backend,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        if testForceInstallFailure == true {
            throw AppleSpeechError.localeInstallFailed(underlying: CocoaError(.fileReadUnknown))
        }
        if testSkipLocaleInstall == true { return }
        if await isLocaleInstalled(locale.identifier) == true { return }

        let transcriber = makeTranscriber(locale: locale)
        let status = await AssetInventory.status(forModules: [transcriber])
        if status == .installed { return }

        if testForceReserveFailure == false {
            let reserved = try await AssetInventory.reserve(locale: locale)
            if reserved == false {
                throw AppleSpeechError.allocationLimitReached
            }
        }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        else {
            return
        }

        let progress = request.progress
        let progressTask = Task {
            var lastTick = Date.distantPast
            while Task.isCancelled == false && progress.isFinished == false {
                let now = Date()
                if now.timeIntervalSince(lastTick) >= ProgressReporting.throttleInterval {
                    lastTick = now
                    onProgress(
                        DownloadProgress(
                            modelId: modelId,
                            backend: backend,
                            currentFile: locale.identifier,
                            filesCompleted: 0,
                            filesTotal: 1,
                            bytesCompleted: Int64(progress.completedUnitCount),
                            bytesTotal: progress.totalUnitCount > 0
                                ? Int64(progress.totalUnitCount) : nil,
                            bytesPerSecond: nil
                        )
                    )
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        defer { progressTask.cancel() }
        try await request.downloadAndInstall()
    }

    static func releaseLocale(_ locale: Locale) async {
        _ = await AssetInventory.release(reservedLocale: locale)
    }

    static func transcribe(
        samples: [Float],
        locale: Locale,
        prompt: String?
    ) async throws -> [AppleSpeechResultMapping.WordSpan] {
        if testForceTranscriptionFailure == true {
            throw AppleSpeechError.transcriptionFailed
        }
        if let spans = testTranscriptionSpans { return spans }
        if testSkipLiveTranscription == true { return [] }

        let transcriber = makeTranscriber(locale: locale)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw AppleSpeechError.audioConversionFailed
        }

        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )
        guard let sourceFormat else {
            throw AppleSpeechError.audioConversionFailed
        }

        let pcmBuffer = try makePCMBuffer(samples: samples, format: sourceFormat)
        let inputs: [AnalyzerInput]
        if sourceFormat == analyzerFormat {
            inputs = [AnalyzerInput(buffer: pcmBuffer)]
        }
        else {
            inputs = try convertToAnalyzerInputs(
                buffer: pcmBuffer,
                sourceFormat: sourceFormat,
                targetFormat: analyzerFormat
            )
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let inputSequence = AsyncStream<AnalyzerInput> { continuation in
            for input in inputs {
                continuation.yield(input)
            }
            continuation.finish()
        }

        let resultsTask = Task { () -> [AppleSpeechResultMapping.WordSpan] in
            var spans: [AppleSpeechResultMapping.WordSpan] = []
            for try await result in transcriber.results {
                guard result.isFinal == true else { continue }
                spans.append(contentsOf: extractWordSpans(from: result.text))
            }
            return spans
        }

        try await analyzer.start(inputSequence: inputSequence)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        _ = prompt
        return try await resultsTask.value
    }

    // MARK: - Private

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
    }

    private static func makePCMBuffer(samples: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AppleSpeechError.audioConversionFailed
        }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else {
            throw AppleSpeechError.audioConversionFailed
        }
        samples.withUnsafeBufferPointer { src in
            channel.update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }

    private static func convertToAnalyzerInputs(
        buffer: AVAudioPCMBuffer,
        sourceFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) throws -> [AnalyzerInput] {
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AppleSpeechError.audioConversionFailed
        }
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw AppleSpeechError.audioConversionFailed
        }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed == true {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else {
            throw AppleSpeechError.audioConversionFailed
        }
        return [AnalyzerInput(buffer: outBuffer)]
    }

    static func extractWordSpans(from attributed: AttributedString) -> [AppleSpeechResultMapping.WordSpan] {
        var spans: [AppleSpeechResultMapping.WordSpan] = []
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            guard text.isEmpty == false else { continue }
            guard let timeRange = run.audioTimeRange else { continue }
            let start = timeRange.start.seconds
            let end = timeRange.end.seconds
            guard end > start else { continue }
            spans.append(.init(text: text, start: start, end: end))
        }
        return spans
    }
}

/// Availability-gated transcriber construction; lives in the excluded LiveAPI shim.
enum AppleSpeechTranscriberBridge {
    static func make(model: String) throws -> any Transcriber {
        if #available(macOS 26, *) {
            guard AppleSpeechBackend.isAvailable == true else {
                throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
            }
            return AppleSpeechBackend(model: model)
        }
        throw BackendTranscriberError.unavailable(AppleSpeechSupport.unavailableMessage())
    }
}

enum AppleSpeechError: Error, LocalizedError, Sendable {
    case runtimeUnavailable
    case localeUnsupported(String)
    case localeInstallFailed(underlying: any Error)
    case transcriptionFailed
    case audioConversionFailed
    case allocationLimitReached

    var errorDescription: String? {
        switch self {
            case .runtimeUnavailable:
                return AppleSpeechSupport.unavailableMessage()
            case .localeUnsupported(let id):
                return "Locale '\(id)' is not supported by Apple Speech"
            case .localeInstallFailed(let underlying):
                return "Apple Speech locale install failed: \(underlying)"
            case .transcriptionFailed:
                return "Apple Speech transcription failed"
            case .audioConversionFailed:
                return "Apple Speech audio conversion failed"
            case .allocationLimitReached:
                return """
                    Apple Speech locale limit reached; deallocate an unused locale with \
                    'superscribe model --rm <locale> --backend appleSpeech'
                    """
        }
    }
}
