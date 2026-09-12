import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import SuperscribeKit

internal actor LoadOnceGate {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markFirstEntered() -> Void {
        self.entered = true
        let pending = self.enteredWaiters
        self.enteredWaiters.removeAll()
        for cont in pending { cont.resume() }
    }

    func waitUntilFirstEntered() async -> Void {
        if self.entered == true { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.enteredWaiters.append(cont)
        }
    }

    func waitForRelease() async -> Void {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.releaseWaiters.append(cont)
        }
    }

    func release() -> Void {
        let pending = self.releaseWaiters
        self.releaseWaiters.removeAll()
        for cont in pending { cont.resume() }
    }
}
