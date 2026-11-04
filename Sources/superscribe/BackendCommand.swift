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

    @Option(name: .long, help: "Set the default backend for the selected type.")
    var setDefault: String?

    @Flag(name: [.long, .customLong("caps")], help: "Print capabilities of the selected type's default backend.")
    var capabilities: Bool = false

    @OptionGroup var backendType: BackendTypeOptions

    mutating func validate() throws -> Void {
        try assertMutuallyExclusive([("--list", self.list), ("--set-default", self.setDefault != nil), ("--capabilities", self.capabilities)])
        if let id = self.setDefault { _ = try self.defaultBackendMutation(for: id) }
    }

    mutating func run() async throws -> Void {
        if let id = self.setDefault {
            try await UserConfig.update(self.defaultBackendMutation(for: id))
            print("Default backend set to '\(id)'.")
        }
        else if self.capabilities == true {
            try self.printCapabilities()
        }
        else {
            let config = try UserConfig.load()
            if self.backendType.isolator == true {
                Self.printBackends(IsolatorBackend.allCases, defaultBackend: config.resolvedDefaultIsolatorBackend())
            }
            else if self.backendType.diarizer == true {
                Self.printBackends(DiarizerBackend.allCases, defaultBackend: config.resolvedDefaultDiarizerBackend())
            }
            else {
                Self.printBackends(Backend.allCases, defaultBackend: config.resolvedDefaultBackend(), availability: Self.availabilityNote)
            }
        }
    }

    private func defaultBackendMutation(for id: String) throws -> @Sendable (inout UserConfig) -> Void {
        if self.backendType.isolator == true {
            let backend = try Self.requireBackend(id, as: IsolatorBackend.self)
            return { $0.setDefaultIsolatorBackend(backend) }
        }
        if self.backendType.diarizer == true {
            let backend = try Self.requireBackend(id, as: DiarizerBackend.self)
            return { $0.setDefaultDiarizerBackend(backend) }
        }
        let backend = try Self.requireBackend(id, as: Backend.self)
        return { $0.setDefaultBackend(backend) }
    }

    private static func requireBackend<B: RawRepresentable & CaseIterable>(_ id: String, as type: B.Type) throws -> B where B.RawValue == String {
        guard let backend = B(rawValue: id) else {
            throw ValidationError("Unknown backend '\(id)'. Available: \(B.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        return backend
    }

    private static func printBackends<B: RawRepresentable & Equatable>(
        _ backends: [B], defaultBackend: B, availability: (B) -> String = { _ in "" }
    ) -> Void where B.RawValue == String {
        for backend in backends {
            let marker =
                if backend == defaultBackend { "  (default)" }
                else { "" }
            print("  \(backend.rawValue)\(marker)\(availability(backend))")
        }
    }

    private static func availabilityNote(for backend: Backend) -> String {
        if backend == .appleSpeech && AppleSpeechSupport.isRuntimeAvailable() == false {
            return "  (requires macOS 26+)"
        }
        return ""
    }

    private func printCapabilities() throws -> Void {
        let caps: BackendCapabilities
        let modelArguments: String
        if self.backendType.isolator == true {
            caps = try UserConfig.load().resolvedDefaultIsolatorBackend().capabilities
            modelArguments = "--isolator --list"
        }
        else if self.backendType.diarizer == true {
            caps = try UserConfig.load().resolvedDefaultDiarizerBackend().capabilities
            modelArguments = "--diarizer --list"
        }
        else {
            let (backend, model) = try BackendManager.resolveBackendAndModel(cliBackend: nil, cliModel: nil)
            caps = try BackendManager.makeTranscriber(backend: backend, model: model).capabilities
            modelArguments = "--list --remote --backend \(backend.rawValue)"
        }
        let fmt = caps.requiredAudioFormat

        print("Backend:        \(caps.displayName)")
        print("Audio format:   \(fmt.sampleRate) Hz, \(fmt.channels == 1 ? "mono" : "\(fmt.channels) channels")")
        print("Default model:  \(caps.defaultModelId)")
        print("")
        print("Use `superscribe model \(modelArguments)` for the full catalog.")
    }
}
