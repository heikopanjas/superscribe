import ArgumentParser
import Foundation
import SuperscribeKit

struct BackendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backend",
        abstract: "List available backends, set the default, or show capabilities."
    )

    @Flag(name: .long, help: "List available backends. Implicit when no other verb is given.")
    var list: Bool = false

    @Option(name: .long, help: "Set the default backend.")
    var setDefault: Backend?

    @Flag(name: [.long, .customLong("caps")], help: "Print capabilities of the current default backend.")
    var capabilities: Bool = false

    mutating func run() throws {
        if let backend = setDefault {
            var config = UserConfig.load()
            config.setDefaultBackend(backend)
            try config.save()
            print("Default backend set to '\(backend.rawValue)'.")
        }
        else if capabilities == true {
            try printCapabilities()
        }
        else {
            // Default verb: --list (explicit or implicit).
            let config = UserConfig.load()
            let userDefault = config.resolvedDefaultBackend()
            for backend in Backend.allCases {
                let marker = (backend == userDefault) ? "  (default)" : ""
                print("  \(backend.rawValue)\(marker)")
            }
        }
    }

    private func printCapabilities() throws {
        let (backend, model) = BackendManager.resolveBackendAndModel(cliBackend: nil, cliModel: nil)
        let transcriber = try BackendManager.makeTranscriber(backend: backend, model: model)
        let caps = transcriber.capabilities
        let fmt = caps.requiredAudioFormat

        print("Backend:        \(caps.displayName)")
        print("Audio format:   \(fmt.sampleRate) Hz, \(fmt.channels == 1 ? "mono" : "\(fmt.channels) channels")")
        print("Default model:  \(caps.defaultModelId)")
        print("")
        print("Use `superscribe model --list --remote --backend \(backend.rawValue)` for the full catalog.")
    }
}
