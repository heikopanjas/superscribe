import Darwin
import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Cross-process configuration transactions", .serialized, ResetSharedStateTrait())
struct CrossProcessPersistenceTests {
    @Test func externalWriterAndAsyncUpdateRetainBothFields() async throws -> Void {
        try await TestHelpers.withTempDirectory { root in
            let ready = root.appendingPathComponent("ready")
            let release = root.appendingPathComponent("release")
            try #require(mkfifo(ready.path, 0o600) == 0)
            try #require(mkfifo(release.path, 0o600) == 0)
            try UserConfig().save()
            let script = """
                import fcntl, json, sys
                config, ready, release = sys.argv[1:]
                with open(config + '.lock', 'a') as lock:
                    fcntl.flock(lock, fcntl.LOCK_EX)
                    with open(ready, 'w') as signal: signal.write('ready')
                    with open(release) as signal: signal.read()
                    with open(config) as source: value = json.load(source)
                    value['defaultModels']['parakeet'] = 'v3'
                    with open(config, 'w') as target: json.dump(value, target)
                """
            async let process = ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", script, UserConfig.configFileURL.path, ready.path, release.path])
            _ = try await BlockingWorker(label: "test.pipe.read").run { _ in
                let handle = try FileHandle(forReadingFrom: ready)
                defer { try? handle.close() }
                return handle.readDataToEndOfFile()
            }
            let entered = TestSignal()
            try await FileTransaction.$lockOperation.withValue(
                { descriptor, operation in
                    entered.signal()
                    return flock(descriptor, operation)
                },
                operation: {
                    let update = Task { try await UserConfig.update { $0.setDefaultBackend(.whisperCpp) } }
                    await entered.wait()
                    try await BlockingWorker(label: "test.pipe.write").run { _ in
                        let handle = try FileHandle(forWritingTo: release)
                        defer { try? handle.close() }
                        try handle.write(contentsOf: Data([1]))
                    }
                    try await update.value
                })
            #expect(try await process.status == 0)
            let config = try UserConfig.load()
            #expect(config.defaultModel(for: .parakeet) == "v3")
            #expect(config.resolvedDefaultBackend() == .whisperCpp)
        }
    }
}
