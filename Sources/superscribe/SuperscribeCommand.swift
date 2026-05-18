import ArgumentParser
import SuperscribeKit

@main
struct Superscribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "superscribe",
        abstract: "Transcribe podcasts from isolated speaker tracks.",
        version: "0.4.0",
        subcommands: [TranscribeCommand.self, MergeCommand.self, RunCommand.self, ModelsCommand.self, BackendsCommand.self]
    )
}
