import Testing

@Suite("Smoke", .serialized, ResetSharedStateTrait())
struct SmokeTests {
    @Test func packageBuilds() -> Void {
        #expect(Bool(true))
    }
}
