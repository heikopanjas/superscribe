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
    private let now: @Sendable () -> TimeInterval
    private var lastEmitAt: TimeInterval = -.infinity
    private var startedAt: TimeInterval
    private var windowStart: TimeInterval
    private var windowStartBytes: Int64 = 0
    private var lastThroughput: Double?

    init(
        modelId: String,
        backend: Backend,
        filesTotal: Int,
        bytesTotal: Int64?,
        onProgress: @Sendable @escaping (DownloadProgress) -> Void,
        now: @Sendable @escaping () -> TimeInterval = { return ProcessInfo.processInfo.systemUptime }
    ) {
        self.modelId = modelId
        self.backend = backend
        self.filesTotal = filesTotal
        self.bytesTotal = bytesTotal
        self.onProgress = onProgress
        self.now = now
        self.startedAt = now()
        self.windowStart = self.startedAt
    }

    func startFile(name: String) -> Void {
        self.currentFile = name
        return
    }

    func add(bytes: Int64) -> Void {
        self.bytesCompleted += bytes
        self.emit(force: false)
    }

    func completeFile() -> Void {
        self.filesCompleted += 1
        self.emit(force: true)
    }

    func flush() -> Void {
        self.emit(force: true)
    }

    private func emit(force: Bool) -> Void {
        let now = self.now()
        if force == false && (now - self.lastEmitAt) < ProgressReporting.throttleInterval {
            return
        }
        let windowElapsed = (now - self.windowStart)
        if windowElapsed >= 1.0 {
            let delta = self.bytesCompleted - self.windowStartBytes
            if delta > 0 {
                self.lastThroughput = Double(delta) / windowElapsed
            }
            self.windowStart = now
            self.windowStartBytes = self.bytesCompleted
        }
        let reported: Double? = {
            if let t = self.lastThroughput { return t }
            let total = (now - self.startedAt)
            guard total > 0, self.bytesCompleted > 0 else { return nil }
            return Double(self.bytesCompleted) / total
        }()
        self.lastEmitAt = now
        self.onProgress(
            DownloadProgress(
                modelId: self.modelId,
                backend: self.backend,
                currentFile: self.currentFile,
                filesCompleted: self.filesCompleted,
                filesTotal: self.filesTotal,
                bytesCompleted: self.bytesCompleted,
                bytesTotal: self.bytesTotal,
                bytesPerSecond: reported
            )
        )
    }
}
