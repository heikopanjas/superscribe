import Foundation
import MLX

@testable import SuperscribeKit

/// Swift Testing's XCTest image is not always registered in NSBundle.allBundles.
enum IntegrationMetalResources {
    private final class Marker: NSObject {}

    static let configure: Bool = {
        let root = Bundle(for: Marker.self).bundleURL.deletingLastPathComponent()
        guard let path = try? MetalLibraryLocation.resolve(executable: nil, bundles: [root]) else { return false }
        GPU.metallib = path
        return true
    }()
}
