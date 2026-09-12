import Foundation

/// Joins analysis and result collection, including framework shutdown on failure.
internal struct AppleSpeechAnalysis: Sendable {
    internal var start: @Sendable () async throws -> Void
    internal var finalize: @Sendable () async throws -> Void
    internal var collect: @Sendable () async throws -> [AppleSpeechResultMapping.WordSpan]
    internal var cancel: @Sendable () async -> Void

    private enum Event: Sendable {
        case analyzed
        case results([AppleSpeechResultMapping.WordSpan])
    }

    private actor Completion {
        private(set) var succeeded = false

        func finish() -> Void {
            self.succeeded = true
            return
        }
    }

    internal func run() async throws -> [AppleSpeechResultMapping.WordSpan] {
        let completion = Completion()
        let (cancellation, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        return try await withThrowingTaskGroup(of: Event.self) { group in
            group.addTask {
                try await self.start()
                try await self.finalize()
                return .analyzed
            }
            group.addTask {
                return .results(try await self.collect())
            }
            group.addTask {
                // This stream has no values. Cancellation wakes its suspended iterator.
                var iterator = cancellation.makeAsyncIterator()
                _ = await iterator.next()
                if await completion.succeeded == false {
                    await self.cancel()
                }
                throw CancellationError()
            }
            defer { group.cancelAll() }
            var finished = 0
            var spans: [AppleSpeechResultMapping.WordSpan] = []
            for try await event in group {
                switch event {
                    case .analyzed:
                        finished += 1
                    case .results(let result):
                        spans = result
                        finished += 1
                }
                if finished == 2 { break }
            }
            try Task.checkCancellation()
            await completion.finish()
            return spans
        }
    }
}
