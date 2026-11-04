import MLX
import Metal
import Testing

@Suite("Metal compilation")
struct MetalCompilationTests {
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "This runner has no Metal GPU; shader compilation is still checked by the build"))
    func executesCompiledShaders() throws -> Void {
        try #require(IntegrationMetalResources.configure == true)
        Device.withDefaultDevice(.gpu) {
            let result = (MLXArray([Float(1), 2, 3]) * 2).asArray(Float.self)
            #expect(result == [2, 4, 6])
        }
    }
}
