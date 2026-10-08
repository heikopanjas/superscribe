import Foundation
import Testing

@testable import SuperscribeKit
@testable import superscribe

@Suite("Diarization CLI", .serialized, ResetSharedStateTrait())
struct DiarizationCLITests {
    @Test func templateAcceptsPathsAndMixedTrackObjects() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            for name in ["host.wav", "panel.wav"] { try Data([0]).write(to: root.appendingPathComponent(name)) }
            let mapping = root.appendingPathComponent("tracks.json")
            try Data(#"{"host": "host.wav", "panel": {"file": "panel.wav", "diarize": true, "speakers": ["Alice", "Bob"]}}"#.utf8).write(to: mapping)
            let tracks = try TrackMappingLoader.load(from: mapping, relativeTo: root)
            #expect(tracks.map(\.speaker) == ["host", "panel"])
            #expect(tracks[0].diarization == nil)
            #expect(tracks[1].diarization == TrackDiarization(speakerNames: ["Alice", "Bob"]))
            #expect(tracks[1].file.lastPathComponent == "panel.wav")
        }
    }

    @Test(arguments: [#"{"panel": {"file": "panel.wav", "speakers": ["Alice"]}}"#, #"{"panel": {"diarize": true}}"#])
    func malformedMixedEntriesAreRejected(json: String) throws -> Void {
        try TestHelpers.withTempDirectory { root in
            let mapping = root.appendingPathComponent("tracks.json")
            try Data(json.utf8).write(to: mapping)
            #expect(throws: DecodingError.self) { _ = try TrackMappingLoader.load(from: mapping, relativeTo: root) }
        }
    }

    @Test func objectWithoutDiarizeIsAnIsolatedTrack() throws -> Void {
        try TestHelpers.withTempDirectory { root in
            try Data([0]).write(to: root.appendingPathComponent("solo.wav"))
            let mapping = root.appendingPathComponent("tracks.json")
            try Data(#"{"solo": {"file": "solo.wav", "diarize": false}}"#.utf8).write(to: mapping)
            #expect(try TrackMappingLoader.load(from: mapping, relativeTo: root).first?.diarization == nil)
        }
    }

    @Test func mixedOptionAddsDiarizedTracksNamedAfterTheirFiles() throws -> Void {
        let options = try TranscribeOptions.parse(["--track", "host=/a/host.wav", "--mixed", "/a/guests.m4a"])
        let tracks = options.trackInputs
        #expect(tracks.map(\.speaker) == ["host", "guests"])
        #expect(tracks[0].diarization == nil)
        #expect(tracks[1].diarization == TrackDiarization())
    }

    @Test(arguments: [["--input", "t.json", "--mixed", "a.wav"], ["--create-input", ".", "--mixed", "a.wav"]])
    func mixedConflictsWithTemplateOptions(arguments: [String]) -> Void {
        #expect(throws: (any Error).self) { _ = try TranscribeCommand.parse(arguments) }
    }

    @Test(arguments: [["--diarizer", "--backend", "parakeet"], ["--diarizer", "--remote"], ["--diarizer", "--set-default", "x"], ["--diarizer", "--json"]])
    func diarizerRejectsBackendOptions(arguments: [String]) -> Void {
        #expect(throws: (any Error).self) { _ = try ModelCommand.parse(arguments) }
    }

    @Test func runnerCreatesADiarizerOnlyForMixedTracks() async throws -> Void {
        let audio = try TestHelpers.makeTemp16kMonoFloatWAV(name: "runner-mixed", durationSeconds: 2)
        defer { try? FileManager.default.removeItem(at: audio) }
        let created = Counter()
        let dependencies = PipelineRunner.Dependencies(
            resolveBackendAndModel: { _, _ in (.parakeet, "mock") },
            ensureModelInstalled: { _, _ in },
            makeTranscriber: { _, _ in MockTranscriber() },
            makeDiarizer: {
                await created.increment()
                return try StubDiarizer(slots: Array(repeating: 0, count: 100) + Array(repeating: 1, count: 100))
            },
            logBackend: { _, _ in },
            clearProgressLine: {}
        )
        for diarization in [TrackDiarization?.none, TrackDiarization(speakerNames: ["Alice", "Bob"])] {
            let result = try await PipelineRunner.run(
                options: PipelineRunOptions(
                    cliBackend: nil, cliModel: nil, tracks: [TrackInput(speaker: "panel", file: audio, diarization: diarization)],
                    transcriptionConfig: TranscriptionConfig(language: "en", prompt: nil), analyzerConfig: AnalyzerConfig(), useCache: false),
                dependencies: dependencies)
            if diarization != nil { #expect(result.transcript.tracks.map(\.speaker) == ["Alice", "Bob"]) }
        }
        #expect(await created.value == 1)
    }
}
