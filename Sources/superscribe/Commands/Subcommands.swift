import ArgumentParser

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Detect speech in each track and produce an intermediate transcript."
    )

    @OptionGroup var options: TranscribeOptions

    mutating func run() async throws {
        throw NotImplemented(subcommand: "transcribe")
    }
}

struct MergeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "merge",
        abstract: "Merge an intermediate transcript into a formatted output."
    )

    @Argument(help: "Path to the intermediate `.superscribe.json` file.")
    var intermediateFile: String

    @OptionGroup var options: MergeOptions

    mutating func run() async throws {
        throw NotImplemented(subcommand: "merge")
    }
}

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Transcribe and merge in a single pass."
    )

    @OptionGroup var transcribeOptions: TranscribeOptions
    @OptionGroup var mergeOptions: MergeOptions

    @Flag(name: .long, help: "Save the intermediate file (default: discard).")
    var keepIntermediate: Bool = false

    mutating func run() async throws {
        throw NotImplemented(subcommand: "run")
    }
}

struct NotImplemented: Error, CustomStringConvertible {
    let subcommand: String
    var description: String { "`\(subcommand)` is not implemented yet" }
}
