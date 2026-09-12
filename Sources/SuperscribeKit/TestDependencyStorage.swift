import Foundation

/// Mutable dependency configuration shared only by tasks in one explicit scope.
/// All reads and writes are protected by the lock; values never escape by reference.
internal final class TestDependencyStorage<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    internal init(_ state: State) {
        self.state = state
    }

    internal subscript<Value>(keyPath: WritableKeyPath<State, Value>) -> Value {
        get {
            return self.lock.withLock { return self.state[keyPath: keyPath] }
        }
        set {
            self.lock.withLock { self.state[keyPath: keyPath] = newValue }
        }
    }
}
