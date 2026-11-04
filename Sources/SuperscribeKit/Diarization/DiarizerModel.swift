import FluidAudio
import Foundation

/// The Nemotron 3 Diarization Core ML model superscribe installs for mixed tracks.
public enum DiarizerModel {
    /// Stable identifier shown by the CLI.
    public static let id = "nemotron-3-diarization"
    /// Hugging Face repository hosting the Core ML conversion (ungated, OpenMDW-1.1).
    public static let repoId = Repo.nemotron3Diarization.rawValue

    /// Streaming preset: best accuracy and speaker counting among the Neural Engine bundles.
    internal static let config = Nemotron3Config.fast128
    /// Records the upstream checkpoint so a FluidAudio weights bump replaces a stale installation.
    internal static let weightsMarker = ModelNames.Nemotron3.weightsVersionFile

    /// Flattened installation holding the preset bundle beside the silence embedding.
    public static func installPath() throws -> URL {
        return try ModelPathValidation.resolve("\(Self.id)-fast128", under: SuperscribePaths.diarizerModelsDirectory())
    }

    /// Checks the bundle, embedding, and weights marker without loading the model.
    public static func isInstalled(at path: URL) -> Bool {
        guard ModelArtifacts.bundle(at: path.appendingPathComponent(Self.config.modelFileName)) == true,
            ModelArtifacts.nonemptyFile(at: path.appendingPathComponent(ModelNames.Nemotron3.silenceEmbeddingFile)) == true
        else { return false }
        let marker = try? String(contentsOf: path.appendingPathComponent(Self.weightsMarker), encoding: .utf8)
        return marker == ModelNames.Nemotron3.weightsVersion
    }

    /// Repository files for the preset bundle (prefix stripped) and the root silence embedding.
    internal static func files(in siblings: [HuggingFaceHub.HFSibling]) -> [ModelDownloadFile] {
        return ModelDownloadFile.select(
            from: siblings, bundles: [Self.config.modelFileName], files: [ModelNames.Nemotron3.silenceEmbeddingFile], under: "\(Self.config.hubSubdirectory)/")
    }

    /// Marks a complete staging directory with the weights version it was downloaded for.
    internal static func writeMarker(in directory: URL) throws -> Void {
        try Data(ModelNames.Nemotron3.weightsVersion.utf8).write(to: directory.appendingPathComponent(Self.weightsMarker), options: .atomic)
    }
}
