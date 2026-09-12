import ArgumentParser
import Foundation
import Testing

@testable import superscribe

@Suite("CLI utilities", .serialized, ResetSharedStateTrait())
struct CLIUtilitiesTests {
    @Test func assertMutuallyExclusiveAllowsOneVerb() throws -> Void {
        try assertMutuallyExclusive([
            ("--list", true),
            ("--clear", false)
        ])
    }

    @Test func assertMutuallyExclusiveThrowsForMultiple() -> Void {
        #expect(throws: ValidationError.self) {
            try assertMutuallyExclusive([
                ("--list", true),
                ("--clear", true)
            ])
        }
    }

    @Test func formatDurationSeconds() -> Void {
        #expect(formatDuration(12.3) == "12.3s")
    }

    @Test func formatDurationMinutes() -> Void {
        #expect(formatDuration(125.0) == "2m 05.0s")
    }

    @Test func printErrWritesToStderr() -> Void {
        printErr("test-stderr-line\n")
    }
}
