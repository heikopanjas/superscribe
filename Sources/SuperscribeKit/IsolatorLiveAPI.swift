import AVFoundation
import DemucsAudio
import DemucsMLX
import Foundation
import MLX

/// External model and GPU operations. Installation policy and audio lifecycle remain covered.
internal enum IsolatorLiveAPI {
    private final class ResourceMarker: NSObject {}

    private static let runtimeConfiguration: Result<Void, any Error> = Result {
        if let existing = GPU.metallib, FileManager.default.isReadableFile(atPath: existing.path) == true { return }
        let owner = Bundle(for: ResourceMarker.self)
        let bundles = [owner, Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        let roots = bundles.flatMap { [$0.bundleURL, $0.resourceURL].compactMap { $0 } } + [owner.bundleURL.deletingLastPathComponent()]
        GPU.metallib = try MetalLibraryLocation.resolve(executable: Bundle.main.executableURL, bundles: roots)
    }

    internal static let modelOperations = IsolatorModelOperations(
        validate: { model, path in try Separator.verifyAssets(model: model.demucsModel, cacheDirectory: path) },
        download: { model, path, progress in
            guard ModelHub.downloadsEnabled == true else { throw DemucsError.missingModel("Model downloads are disabled; install \(model.rawValue) before offline use") }
            try await ModelHub.download(model.demucsModel, to: path) { update in
                progress(
                    DownloadProgress(
                        modelId: model.rawValue, backend: nil, currentFile: model.rawValue,
                        filesCompleted: 0, filesTotal: 2, bytesCompleted: update.bytesReceived,
                        bytesTotal: update.bytesExpected, bytesPerSecond: nil))
            }
        },
        downloadSize: { ModelHub.downloadSize(of: $0.demucsModel) })

    internal static func open(model: IsolatorModel, directory: URL) async throws -> any VocalIsolationSession {
        try Self.runtimeConfiguration.get()
        let separator = try await Separator.load(model: model.demucsModel, cacheDirectory: directory, options: model.separationOptions, download: .never)
        return LiveSession(separator: separator)
    }

    private actor LiveSession: VocalIsolationSession {
        nonisolated let sampleRate: Int
        nonisolated let channels: Int
        private let separator: Separator

        init(separator: Separator) {
            self.separator = separator
            self.sampleRate = separator.sampleRate
            self.channels = separator.audioChannels
        }

        func vocals(samples: [Float], frames: Int) async throws -> [Float] {
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(self.sampleRate), channels: AVAudioChannelCount(self.channels), interleaved: false),
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                let pointers = buffer.floatChannelData
            else { throw DemucsError.invalidInput("Cannot allocate the isolation input buffer") }
            buffer.frameLength = AVAudioFrameCount(frames)
            for channel in 0 ..< self.channels {
                for index in 0 ..< frames { pointers[channel][index] = samples[channel * frames + index] }
            }
            let tensor = try DemucsAudio.tensor(from: buffer, sampleRate: self.sampleRate)
            let result = try await self.separator.separate(tensor)
            let vocals = try DemucsAudio.pcmBuffer(from: result.stem("vocals"), sampleRate: self.sampleRate)
            guard let data = vocals.floatChannelData else { throw DemucsError.invalidInput("Cannot read isolated vocals") }
            let count = Int(vocals.frameLength)
            let channelCount = Int(vocals.format.channelCount)
            var mono = [Float](repeating: 0, count: count)
            for channel in 0 ..< channelCount {
                for index in 0 ..< count { mono[index] += data[channel][index] / Float(channelCount) }
            }
            return mono
        }
    }
}
