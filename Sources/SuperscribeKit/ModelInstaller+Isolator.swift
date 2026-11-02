import Foundation

extension ModelInstaller {
    @TaskLocal internal static var isolatorOperations = IsolatorLiveAPI.modelOperations

    /// First use installs the selected model. Subsequent damage or removal requires explicit repair.
    @discardableResult
    public static func installIsolator(
        model: IsolatorModel, allowRepair: Bool = false,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let path = try model.installPath()
        let receipt = model.receiptURL
        let operations = Self.isolatorOperations
        return try await ModelLifecycleCoordinator.shared.withLock {
            let valid = await Self.validateIsolator(model, at: path, operations: operations)
            try Task.checkCancellation()
            if valid == false {
                if allowRepair == false && (FileManager.default.fileExists(atPath: receipt.path) == true || FileManager.default.fileExists(atPath: path.path) == true) {
                    throw InputValidationError("Isolation model \(model.rawValue) is missing or invalid. Run: superscribe model --isolator --download \(model.rawValue)")
                }
                try Self.preflightDiskSpace(requiredBytes: operations.downloadSize(model), installPath: path)
                _ = try await Self.stageAndPublish(
                    finalDir: path,
                    download: { try await operations.download(model, $0, onProgress) },
                    validate: { await Self.validateIsolator(model, at: $0, operations: operations) })
            }
            try await FileTransaction.worker.run { _ in try Self.writeIsolatorReceipt(model, at: receipt) }
            return path
        }
    }

    public static func isIsolatorInstalled(_ model: IsolatorModel) async -> Bool {
        guard let path = try? model.installPath() else { return false }
        return await Self.validateIsolator(model, at: path, operations: Self.isolatorOperations)
    }

    @discardableResult
    public static func removeIsolator(model: IsolatorModel) async throws -> Bool {
        let path = try model.installPath()
        let receipt = model.receiptURL
        return try await ModelLifecycleCoordinator.shared.withLock {
            guard FileManager.default.fileExists(atPath: path.path) == true else { return false }
            try await FileTransaction.worker.run { _ in
                try Self.writeIsolatorReceipt(model, at: receipt)
                try FileManager.default.removeItem(at: path)
            }
            return true
        }
    }

    private static func validateIsolator(_ model: IsolatorModel, at path: URL, operations: IsolatorModelOperations) async -> Bool {
        return (try? await FileTransaction.worker.run { _ in try operations.validate(model, path) }) != nil
    }

    private static func writeIsolatorReceipt(_ model: IsolatorModel, at url: URL) throws -> Void {
        try FileTransaction.withLock(for: url) {
            try JSONCoding.configEncoder().encode(model).write(to: url, options: .atomic)
        }
    }
}
