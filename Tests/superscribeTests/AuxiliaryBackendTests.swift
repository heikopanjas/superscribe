import Testing

@testable import SuperscribeKit

@Suite("Isolation and diarization backends", .serialized, ResetSharedStateTrait())
struct AuxiliaryBackendTests {
    @Test func isolatorCapabilitiesAndFactoryDoNotLoadModels() throws -> Void {
        let backend = IsolatorBackend.htdemucs
        let capabilities = backend.capabilities
        #expect(capabilities.displayName == "HTDemucs (DemucsMLX)")
        #expect(capabilities.requiredAudioFormat == AudioFormat(sampleRate: 44_100, channels: 2))
        #expect(capabilities.defaultModelId == IsolatorModel.htdemucs.rawValue)
        for model in IsolatorModel.allCases {
            #expect(try backend.makeIsolator(model: model) is DemucsVocalIsolator)
        }
    }

    @Test func diarizerCapabilitiesAndFactoryDoNotLoadModels() throws -> Void {
        let backend = DiarizerBackend.nemotron
        let capabilities = backend.capabilities
        #expect(capabilities.displayName == "Nemotron 3 (FluidAudio Core ML)")
        #expect(capabilities.requiredAudioFormat == .asr16kMono)
        #expect(capabilities.defaultModelId == DiarizerModel.id)
        #expect(try backend.makeDiarizer() is NemotronDiarizer)
    }
}
