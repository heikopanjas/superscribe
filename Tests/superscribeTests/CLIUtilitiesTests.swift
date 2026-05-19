import ArgumentParser
import Foundation
import Testing

@testable import superscribe

@Suite("CLI utilities")
struct CLIUtilitiesTests {
    @Test func assertMutuallyExclusiveAllowsOneVerb() throws {
        try assertMutuallyExclusive([
            ("--list", true),
            ("--clear", false)
        ])
    }

    @Test func assertMutuallyExclusiveThrowsForMultiple() {
        #expect(throws: ValidationError.self) {
            try assertMutuallyExclusive([
                ("--list", true),
                ("--clear", true)
            ])
        }
    }

    @Test func formatDurationSeconds() {
        #expect(formatDuration(12.3) == "12.3s")
    }

    @Test func formatDurationMinutes() {
        #expect(formatDuration(125.0) == "2m 05.0s")
    }

    @Test func printErrWritesToStderr() {
        printErr("test-stderr-line\n")
    }
}
