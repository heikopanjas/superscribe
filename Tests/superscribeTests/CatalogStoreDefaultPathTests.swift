import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("CatalogStore default path", .serialized, ResetSharedStateTrait())
struct CatalogStoreDefaultPathTests {
    @Test func fileURLWithoutOverride() throws -> Void {
        let prior = CatalogStore.overrideURL
        CatalogStore.overrideURL = nil
        defer { CatalogStore.overrideURL = prior }
        #expect(CatalogStore.fileURL.path.contains("catalog.json") == true)
    }
}
