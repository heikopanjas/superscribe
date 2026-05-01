import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test func packageBuilds() {
        #expect(Bool(true))
    }
}
