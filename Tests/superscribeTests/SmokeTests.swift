import Testing

@Suite("Smoke", .serialized, ResetSharedStateTrait())
struct SmokeTests {
    @Test func packageBuilds() {
        #expect(Bool(true))
    }
}
