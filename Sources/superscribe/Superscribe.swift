import ArgumentParser
import Foundation
import SuperscribeKit

@main
struct Superscribe: AsyncParsableCommand {
    static let toolVersion = "0.7.6"

    static let configuration = CommandConfiguration(
        commandName: "superscribe",
        abstract: "Transcribe podcasts from isolated speaker tracks.",
        subcommands: [TranscribeCommand.self, MergeCommand.self, RunCommand.self, ModelCommand.self, BackendCommand.self, CacheCommand.self]
    )

    @Flag(name: .long, help: "Show the version.")
    var version: Bool = false

    mutating func run() throws {
        if version == true {
            print(Self.toolVersion)
            return
        }
        print(Self.helpMessage())
    }
}
