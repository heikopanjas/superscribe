import Foundation
import Testing

@testable import SuperscribeKit

internal actor Counter {
    private(set) var value = 0
    func increment() -> Void {
        self.value += 1
        return
    }
}
