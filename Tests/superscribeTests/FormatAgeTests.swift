import Foundation
import Testing

@testable import superscribe

@Suite("formatAge", .serialized, ResetSharedStateTrait())
struct FormatAgeTests {
    @Test func underOneMinute() {
        #expect(formatAge(0) == "< 1m ago")
        #expect(formatAge(59) == "< 1m ago")
    }

    @Test func minutes() {
        #expect(formatAge(60) == "1m ago")
        #expect(formatAge(120) == "2m ago")
        #expect(formatAge(3599) == "59m ago")
    }

    @Test func hours() {
        #expect(formatAge(3600) == "1h ago")
        #expect(formatAge(7200) == "2h ago")
    }

    @Test func hoursWithMinutes() {
        #expect(formatAge(3660) == "1h 1m ago")
        #expect(formatAge(5400) == "1h 30m ago")
    }

    @Test func days() {
        #expect(formatAge(86400) == "1d ago")
        #expect(formatAge(172_800) == "2d ago")
    }

    @Test func daysWithHours() {
        #expect(formatAge(90_000) == "1d 1h ago")
        #expect(formatAge(86_400 + 7_200) == "1d 2h ago")
    }
}
