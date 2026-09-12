import AVFoundation
import Foundation
import Speech

/// Speech framework calls and stub/live branching isolated from unit-test coverage
/// (live paths require macOS 26+ and installed locale assets).
@available(macOS 26, *)
enum AppleSpeechLiveAPI {
    @TaskLocal internal static var testState = TestDependencyStorage(TestState())

    internal struct TestState {
        var testSupportedLocaleIds: [String]?
        var testInstalledLocaleIds: [String]?
        var testReservedLocaleIds: [String]?
        var testTranscriptionSpans: [AppleSpeechResultMapping.WordSpan]?
        var testForceInstallFailure = false
        var testForceTranscriptionFailure = false
        var testSkipLiveTranscription = false
        var testForceReserveFailure = false
        var testForceUnsupportedLocale = false
        var testSkipLocaleInstall = false
    }

    @TaskLocal internal static var releaseOperation: (@Sendable (Locale) async -> Void)?
    internal static var testSupportedLocaleIds: [String]? {
        get { return Self.testState[\.testSupportedLocaleIds] }
        set { Self.testState[\.testSupportedLocaleIds] = newValue }
    }
    internal static var testInstalledLocaleIds: [String]? {
        get { return Self.testState[\.testInstalledLocaleIds] }
        set { Self.testState[\.testInstalledLocaleIds] = newValue }
    }
    internal static var testReservedLocaleIds: [String]? {
        get { return Self.testState[\.testReservedLocaleIds] }
        set { Self.testState[\.testReservedLocaleIds] = newValue }
    }

    static func reservedLocaleIds() async -> [String] {
        if let ids = Self.testReservedLocaleIds { return ids }
        return await AssetInventory.reservedLocales.map { AppleSpeechSupport.normalizeLocaleId($0.identifier) }
    }

    internal static var testTranscriptionSpans: [AppleSpeechResultMapping.WordSpan]? {
        get { return Self.testState[\.testTranscriptionSpans] }
        set { Self.testState[\.testTranscriptionSpans] = newValue }
    }
    internal static var testForceInstallFailure: Bool {
        get { return Self.testState[\.testForceInstallFailure] }
        set { Self.testState[\.testForceInstallFailure] = newValue }
    }
    internal static var testForceTranscriptionFailure: Bool {
        get { return Self.testState[\.testForceTranscriptionFailure] }
        set { Self.testState[\.testForceTranscriptionFailure] = newValue }
    }
    internal static var testSkipLiveTranscription: Bool {
        get { return Self.testState[\.testSkipLiveTranscription] }
        set { Self.testState[\.testSkipLiveTranscription] = newValue }
    }
    internal static var testForceReserveFailure: Bool {
        get { return Self.testState[\.testForceReserveFailure] }
        set { Self.testState[\.testForceReserveFailure] = newValue }
    }
    internal static var testForceUnsupportedLocale: Bool {
        get { return Self.testState[\.testForceUnsupportedLocale] }
        set { Self.testState[\.testForceUnsupportedLocale] = newValue }
    }
    internal static var testSkipLocaleInstall: Bool {
        get { return Self.testState[\.testSkipLocaleInstall] }
        set { Self.testState[\.testSkipLocaleInstall] = newValue }
    }

    static func supportedLocaleIds() async -> [String] {
        if let testSupportedLocaleIds = Self.testSupportedLocaleIds { return testSupportedLocaleIds }
        let locales = await SpeechTranscriber.supportedLocales
        return locales.map { AppleSpeechSupport.normalizeLocaleId($0.identifier) }
    }

    static func installedLocaleIds() async -> [String] {
        if let testInstalledLocaleIds = Self.testInstalledLocaleIds { return testInstalledLocaleIds }
        let locales = await SpeechTranscriber.installedLocales
        return locales.map { AppleSpeechSupport.normalizeLocaleId($0.identifier) }
    }

    static func isLocaleInstalled(_ localeId: String) async -> Bool {
        let normalized = AppleSpeechSupport.normalizeLocaleId(localeId)
        let installed = await Self.installedLocaleIds()
        return installed.contains(where: { $0 == normalized })
    }

    static func resolveSupportedLocale(for locale: Locale) async -> Locale? {
        if Self.testForceUnsupportedLocale == true { return nil }
        if let supported = Self.testSupportedLocaleIds {
            let requested = AppleSpeechSupport.normalizeLocaleId(locale.identifier)
            return supported.first(where: { $0 == requested }).map { Locale(identifier: $0) }
        }
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return equivalent
        }
        return nil
    }

    static var assetOperations: AppleSpeechAssetOperations {
        return AppleSpeechAssetOperations(
            resolve: { locale in return await Self.resolveSupportedLocale(for: locale) },
            reserve: { locale in
                if Self.testForceReserveFailure == true { throw AppleSpeechError.allocationLimitReached }
                if Self.testSupportedLocaleIds != nil { return false }
                return try await AssetInventory.reserve(locale: locale)
            },
            release: { locale in await Self.releaseLocale(locale) },
            installation: { locale in
                if Self.testForceInstallFailure == true {
                    throw AppleSpeechError.localeInstallFailed(underlying: CocoaError(.fileReadUnknown))
                }
                if Self.testSkipLocaleInstall == true { return nil }
                if await Self.isLocaleInstalled(locale.identifier) == true { return nil }
                let transcriber = Self.makeTranscriber(locale: locale)
                guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return nil }
                return AppleSpeechInstallation(progress: request.progress, download: { try await request.downloadAndInstall() })
            }
        )
    }

    static func releaseLocale(_ locale: Locale) async -> Void {
        if let operation = Self.releaseOperation {
            await operation(locale)
            return
        }
        _ = await AssetInventory.release(reservedLocale: locale)
    }

    static func transcribe(
        samples: [Float],
        locale: Locale,
        prompt: String?
    ) async throws -> [AppleSpeechResultMapping.WordSpan] {
        if Self.testForceTranscriptionFailure == true {
            throw AppleSpeechError.transcriptionFailed
        }
        if let spans = Self.testTranscriptionSpans { return spans }
        if Self.testSkipLiveTranscription == true { return [] }

        let transcriber = Self.makeTranscriber(locale: locale)
        guard
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            )
        else {
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

        let pcmBuffer = try Self.makePCMBuffer(samples: samples, format: sourceFormat)
        let inputs: [AnalyzerInput]
        if sourceFormat == analyzerFormat {
            inputs = [AnalyzerInput(buffer: pcmBuffer)]
        }
        else {
            inputs = try Self.convertToAnalyzerInputs(
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

        _ = prompt
        return try await AppleSpeechAnalysis(
            start: { try await analyzer.start(inputSequence: inputSequence) },
            finalize: { try await analyzer.finalizeAndFinishThroughEndOfInput() },
            collect: {
                var spans: [AppleSpeechResultMapping.WordSpan] = []
                for try await result in transcriber.results where result.isFinal == true {
                    spans.append(contentsOf: Self.extractWordSpans(from: result.text))
                }
                return spans
            },
            cancel: { await analyzer.cancelAndFinishNow() }
        ).run()
    }

    // MARK: - Private

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        return SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
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
        _ = UnsafeMutableBufferPointer(start: channel, count: samples.count).update(from: samples)
        return buffer
    }

    private static func convertToAnalyzerInputs(
        buffer: AVAudioPCMBuffer,
        sourceFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) throws -> [AnalyzerInput] {
        var inputs: [AnalyzerInput] = []
        try StreamingAudioConverter.convert(buffer: buffer, to: targetFormat) { output in
            guard let copy = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: output.frameLength),
                let destination = copy.floatChannelData?[0], let source = output.floatChannelData?[0]
            else { throw AppleSpeechError.audioConversionFailed }
            copy.frameLength = output.frameLength
            destination.update(from: source, count: Int(output.frameLength))
            inputs.append(AnalyzerInput(buffer: copy))
        }
        return inputs
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
