import Foundation
import Testing

@testable import SuperscribeKit

@Suite("Apple Speech reservation lifecycle", .serialized, ResetSharedStateTrait())
struct AppleSpeechLifecycleTests {
    @Test(arguments: [false, true])
    func reservationResultsBothSucceed(acquired: Bool) async throws -> Void {
        let operations = Self.operations(acquired: acquired)
        let marker = try await AppleSpeechAssetInstaller.$operations.withValue(operations) {
            return try await AppleSpeechAssetInstaller.ensureInstalled(localeId: "en-GB", backend: .appleSpeech, onProgress: { _ in })
        }
        #expect(AppleSpeechSupport.localeId(fromInstallMarker: marker) == "en-US")
    }

    @Test(arguments: [false, true])
    func requestFailureRollsBackOnlyNewReservation(acquired: Bool) async -> Void {
        await confirmation("Release only our new reservation", expectedCount: acquired == true ? 1 : 0) { released in
            var operations = Self.operations(acquired: acquired)
            operations.installation = { _ in throw CocoaError(.fileReadUnknown) }
            operations.release = { locale in
                #expect(AppleSpeechSupport.normalizeLocaleId(locale.identifier) == "en-US")
                released()
            }
            await #expect(throws: CocoaError.self) {
                _ = try await AppleSpeechAssetInstaller.install(localeId: "en-GB", backend: .appleSpeech, operations: operations, onProgress: { _ in })
            }
        }
    }

    @Test func reservationErrorPropagatesWithoutRelease() async -> Void {
        var operations = Self.operations(acquired: false)
        operations.reserve = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        await #expect(throws: CocoaError.self) {
            _ = try await AppleSpeechAssetInstaller.install(localeId: "en-US", backend: .appleSpeech, operations: operations, onProgress: { _ in })
        }
    }

    @Test(arguments: [Int64(0), Int64(10)])
    func installationJoinsProgress(total: Int64) async throws -> Void {
        let (ticks, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        let progress = Progress(totalUnitCount: total)
        var operations = Self.operations(acquired: true)
        operations.installation = { _ in
            return AppleSpeechInstallation(
                progress: progress,
                download: {
                    for await _ in ticks { return }
                })
        }
        let completed = TestDependencyStorage(false)
        _ = try await AppleSpeechAssetInstaller.install(localeId: "en-US", backend: .appleSpeech, operations: operations) { tick in
            #expect(completed[\.self] == false)
            #expect(tick.modelId == "en-US")
            #expect(tick.bytesTotal == (total > 0 ? total : nil))
            continuation.yield()
        }
        completed[\.self] = true
    }

    @Test func downloadFailureJoinsProgressAndRollsBack() async -> Void {
        let (ticks, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        await confirmation("Rollback", expectedCount: 1) { released in
            var operations = Self.operations(acquired: true)
            operations.release = { _ in released() }
            operations.installation = { _ in
                return AppleSpeechInstallation(
                    progress: Progress(totalUnitCount: 1),
                    download: {
                        for await _ in ticks { break }
                        throw CocoaError(.fileWriteUnknown)
                    })
            }
            await #expect(throws: CocoaError.self) {
                _ = try await AppleSpeechAssetInstaller.install(localeId: "en-US", backend: .appleSpeech, operations: operations) { _ in
                    continuation.yield()
                }
            }
        }
    }

    private static func operations(acquired: Bool) -> AppleSpeechAssetOperations {
        return AppleSpeechAssetOperations(
            resolve: { _ in return Locale(identifier: "en-US") },
            reserve: { locale in
                #expect(AppleSpeechSupport.normalizeLocaleId(locale.identifier) == "en-US")
                return acquired
            },
            release: { _ in Issue.record("Unexpected release") },
            installation: { _ in return nil }
        )
    }
}
