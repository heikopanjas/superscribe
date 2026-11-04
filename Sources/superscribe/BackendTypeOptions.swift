import ArgumentParser

/// Shared type selectors for backend and model management.
struct BackendTypeOptions: ParsableArguments {
    @Flag(name: .long, help: "Select transcription (default when no type selector is given).")
    var transcriber: Bool = false

    @Flag(name: .long, help: "Select speaker diarization for mixed tracks.")
    var diarizer: Bool = false

    @Flag(name: .long, help: "Select vocal isolation.")
    var isolator: Bool = false

    mutating func validate() throws -> Void {
        try assertMutuallyExclusive([
            ("--transcriber", self.transcriber),
            ("--diarizer", self.diarizer),
            ("--isolator", self.isolator)
        ])
    }
}
