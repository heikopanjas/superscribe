import Foundation
import Testing

@testable import SuperscribeKit

@Suite("ByteFormatting", .serialized, ResetSharedStateTrait())
struct ByteFormattingTests {
    @Test func formatsBytes() {
        #expect(ByteFormatting.format(512) == "512 B")
        #expect(ByteFormatting.format(0) == "0 B")
    }

    @Test func formatsKiB() {
        #expect(ByteFormatting.format(1024) == "1.0 KiB")
        #expect(ByteFormatting.format(1536) == "1.5 KiB")
    }

    @Test func formatsMiB() {
        #expect(ByteFormatting.format(1024 * 1024) == "1.0 MiB")
    }

    @Test func formatsGiB() {
        #expect(ByteFormatting.format(1024 * 1024 * 1024) == "1.0 GiB")
    }

    @Test func usedInInstallationError() {
        let err = ModelInstallationError.insufficientDiskSpace(
            requiredBytes: 2048,
            availableBytes: 1024,
            path: URL(fileURLWithPath: "/tmp")
        )
        #expect(err.description.contains("2.0 KiB"))
        #expect(err.description.contains("1.0 KiB"))
    }
}
