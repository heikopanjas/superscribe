import Foundation

/// Throttled download progress reporter shared by `ModelDownloader` and encoder installs.
actor DownloadProgressTracker {
    private let modelId: String
    private let backend: Backend
    private let filesTotal: Int
    private let bytesTotal: Int64?
    private let onProgress: @Sendable (DownloadProgress) -> Void

    private var bytesCompleted: Int64 = 0
    private var filesCompleted: Int = 0
    private var currentFile: String = ""
    private var lastEmitAt: Date = .distantPast
    private var startedAt: Date = .distantPast
    private var windowStart: Date = .distantPast
    private var windowStartBytes: Int64 = 0
    private var lastThroughput: Double?

    init(
        modelId: String,
        backend: Backend,
        filesTotal: Int,
        bytesTotal: Int64?,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void
    ) {
        self.modelId = modelId
        self.backend = backend
        self.filesTotal = filesTotal
        self.bytesTotal = bytesTotal
        self.onProgress = onProgress
        let now = Date()
        self.startedAt = now
        self.windowStart = now
    }

    func startFile(name: String) {
        currentFile = name
    }

    func add(bytes: Int64) {
        bytesCompleted += bytes
        emit(force: false)
    }

    func completeFile() {
        filesCompleted += 1
        emit(force: true)
    }

    func flush() {
        emit(force: true)
    }

    private func emit(force: Bool) {
        let now = Date()
        if force == false && now.timeIntervalSince(lastEmitAt) < ProgressReporting.throttleInterval {
            return
        }
        let windowElapsed = now.timeIntervalSince(windowStart)
        if windowElapsed >= 1.0 {
            let delta = bytesCompleted - windowStartBytes
            if delta > 0 {
                lastThroughput = Double(delta) / windowElapsed
            }
            windowStart = now
            windowStartBytes = bytesCompleted
        }
        let reported: Double? = {
            if let t = lastThroughput { return t }
            let total = now.timeIntervalSince(startedAt)
            guard total > 0, bytesCompleted > 0 else { return nil }
            return Double(bytesCompleted) / total
        }()
        lastEmitAt = now
        onProgress(
            DownloadProgress(
                modelId: modelId,
                backend: backend,
                currentFile: currentFile,
                filesCompleted: filesCompleted,
                filesTotal: filesTotal,
                bytesCompleted: bytesCompleted,
                bytesTotal: bytesTotal,
                bytesPerSecond: reported
            )
        )
    }
}
