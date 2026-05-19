import Foundation
import whisper

/// whisper.cpp C API calls and stub/live branching isolated from unit-test coverage
/// (live paths require a real GGML model on disk).
enum WhisperLiveAPI {
    /// When `true`, `releaseContext` is a no-op (covers managed deinit without a real model).
    nonisolated(unsafe) internal static var testSkipContextRelease = false

    static func releaseContext(_ context: OpaquePointer) {
        if testSkipContextRelease == true { return }
        whisper_free(context)
    }

    static func initContext(from binPath: String, ctxParams: whisper_context_params) -> OpaquePointer? {
        whisper_init_from_file_with_params(binPath, ctxParams)
    }

    static func initState(context: OpaquePointer, modelId: String) -> OpaquePointer? {
        if WhisperBackend.isStubModel(modelId), let injected = WhisperBackend.testWhisperStatePointer {
            return injected
        }
        if shouldUseStubAPI(for: modelId) {
            return stubWhisperStatePointer()
        }
        return whisper_init_state(context)
    }

    static func releaseState(
        _ state: OpaquePointer,
        modelId: String,
        usedStubAPI: Bool
    ) {
        if usedStubAPI == true { return }
        if WhisperBackend.isStubModel(modelId), WhisperBackend.testWhisperStatePointer != nil { return }
        whisper_free_state(state)
    }

    static func runFull(
        context: OpaquePointer,
        state: OpaquePointer,
        params: whisper_full_params,
        samples: [Float],
        useStubAPI: Bool
    ) -> Int32 {
        if WhisperBackend.testForceTranscriptionFailed == true {
            return -1
        }
        if useStubAPI == true {
            return 0
        }
        return samples.withUnsafeBufferPointer { buf in
            whisper_full_with_state(context, state, params, buf.baseAddress, Int32(buf.count))
        }
    }

    static func segmentCount(from state: OpaquePointer, modelId: String) -> Int {
        if WhisperBackend.isStubModel(modelId), let segments = WhisperBackend.testWhisperAPISegments {
            return segments.count
        }
        return Int(whisper_full_n_segments_from_state(state))
    }

    static func tokenCount(from state: OpaquePointer, segment: Int, modelId: String) -> Int {
        if WhisperBackend.isStubModel(modelId),
            let segments = WhisperBackend.testWhisperAPISegments,
            segment < segments.count
        {
            return segments[segment].count
        }
        return Int(whisper_full_n_tokens_from_state(state, Int32(segment)))
    }

    static func tokenData(
        from state: OpaquePointer,
        segment: Int,
        token: Int,
        modelId: String
    ) -> whisper_token_data {
        if WhisperBackend.isStubModel(modelId),
            let segments = WhisperBackend.testWhisperAPISegments,
            segment < segments.count,
            token < segments[segment].count
        {
            let entry = segments[segment][token]
            var data = whisper_token_data()
            data.id = entry.id
            data.t0 = entry.t0
            data.t1 = entry.t1
            return data
        }
        return whisper_full_get_token_data_from_state(state, Int32(segment), Int32(token))
    }

    static func tokenText(
        context: OpaquePointer,
        state: OpaquePointer,
        segment: Int,
        token: Int,
        modelId: String
    ) -> String? {
        if WhisperBackend.testForceNilTokenText == true, WhisperBackend.testNilTokenTextSkipsRemaining > 0 {
            WhisperBackend.testNilTokenTextSkipsRemaining -= 1
            return nil
        }
        if WhisperBackend.isStubModel(modelId),
            let segments = WhisperBackend.testWhisperAPISegments,
            segment < segments.count,
            token < segments[segment].count
        {
            return segments[segment][token].token
        }
        guard
            let rawPtr = whisper_full_get_token_text_from_state(
                context, state, Int32(segment), Int32(token)
            )
        else {
            return nil
        }
        return String(cString: rawPtr)
    }

    private static func shouldUseStubAPI(for modelId: String) -> Bool {
        WhisperBackend.testWhisperAPISegments != nil && WhisperBackend.isStubModel(modelId)
    }

    private static func stubWhisperStatePointer() -> OpaquePointer {
        OpaquePointer(bitPattern: 0x2)!
    }
}
