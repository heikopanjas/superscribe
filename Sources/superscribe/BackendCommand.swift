import ArgumentParser
import Foundation
import SuperscribeKit

struct BackendCommand: AsyncParsableCommand {
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

    mutating func validate() throws -> Void {
        try assertMutuallyExclusive([("--list", self.list), ("--set-default", self.setDefault != nil), ("--capabilities", self.capabilities)])
    }

    mutating func run() async throws -> Void {
        if let backend = self.setDefault {
            try await UserConfig.update { $0.setDefaultBackend(backend) }
            print("Default backend set to '\(backend.rawValue)'.")
        }
        else if self.capabilities == true {
            try self.printCapabilities()
        }
        else {
            // Default verb: --list (explicit or implicit).
            let config = try UserConfig.load()
            let userDefault = config.resolvedDefaultBackend()
            for backend in Backend.allCases {
                let marker = (backend == userDefault) ? "  (default)" : ""
                let availability = Self.availabilityNote(for: backend)
                print("  \(backend.rawValue)\(marker)\(availability)")
            }
        }
    }

    private static func availabilityNote(for backend: Backend) -> String {
        if backend == .appleSpeech && AppleSpeechSupport.isRuntimeAvailable() == false {
            return "  (requires macOS 26+)"
        }
        return ""
    }

    private func printCapabilities() throws -> Void {
        let (backend, model) = try BackendManager.resolveBackendAndModel(cliBackend: nil, cliModel: nil)
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
