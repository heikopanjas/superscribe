import Foundation
import SuperscribeKit
import Testing

@Suite("Installed isolation models")
struct IsolatorIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUPERSCRIBE_INTEGRATION_ISOLATION_AUDIO"] != nil, "Supply a local recording and install both isolation models first"))
    func installedModelsPreserveDurationOffline() async throws -> Void {
        let path = try #require(ProcessInfo.processInfo.environment["SUPERSCRIBE_INTEGRATION_ISOLATION_AUDIO"])
        let source = URL(fileURLWithPath: path)
        let expected = try AudioPreparer(targetFormat: .asr16kMono).prepare(url: source)
        let models: [IsolatorModel]
        if let selected = ProcessInfo.processInfo.environment["SUPERSCRIBE_INTEGRATION_ISOLATION_MODEL"] {
            models = [try #require(IsolatorModel(rawValue: selected))]
        }
        else {
            models = IsolatorModel.allCases
        }
        for model in models {
            #expect(await ModelInstaller.isIsolatorInstalled(model) == true)
            let audio = try await DemucsVocalIsolator(model: model).prepare(source: source, targetFormat: .asr16kMono)
            #expect(abs(audio.frameCount - expected.frameCount) <= 1)
        }
    }
}
