# Superscribe implementation status and maintenance

**Last updated:** 2026-11-04

This document maps implemented capabilities to source files and defines maintenance checkpoints. Its filename is retained from the original MVP plan for existing links. Validation results depend on the target OS and available hardware.

[README.md](../README.md) owns CLI usage and options; [the architecture document](podscribe-design.md) explains the processing flow; [AGENTS.md](../AGENTS.md) owns coding and validation policy; [UPDATES.md](../UPDATES.md) records decisions and completed verification.

## Implemented capabilities

| Area | Current behavior | Primary implementation |
|---|---|---|
| Input | Named-speaker tracks, mixed recordings, and JSON track mappings; directory scanning writes templates | [TranscribeCommand](../Sources/superscribe/TranscribeCommand.swift), [TrackMappingLoader](../Sources/superscribe/TrackMappingLoader.swift) |
| Processing order | Optional isolation, PCM preparation, RMS detection or diarization, globally bounded transcription, intermediate transcript | [TranscribePipeline](../Sources/SuperscribeKit/TranscribePipeline.swift) |
| Vocal isolation | HTDemucs and fine-tuned model; bounded sections, overlap blending, and isolated-audio cache identities | [DemucsVocalIsolator](../Sources/SuperscribeKit/DemucsVocalIsolator.swift) |
| Speaker diarization | Nemotron 3; frame assignment, shared turn cleanup, and virtual speaker tracks | [NemotronDiarizer](../Sources/SuperscribeKit/Diarization/NemotronDiarizer.swift), [SpeakerTurnBuilder](../Sources/SuperscribeKit/Diarization/SpeakerTurnBuilder.swift) |
| Transcription | Parakeet, whisper.cpp, and runtime-gated Apple Speech; backend-owned model identity and absolute timed words | [Transcriber](../Sources/SuperscribeKit/Transcriber.swift), [BackendDispatch](../Sources/SuperscribeKit/BackendDispatch.swift) |
| Backend management | All three types support listing, capabilities, and independent saved defaults | [BackendCommand](../Sources/superscribe/BackendCommand.swift), [UserConfig](../Sources/SuperscribeKit/UserConfig.swift) |
| Model management | Transcription catalogs/defaults; local list/download/remove for isolation and diarization; staged installation and explicit isolation repair | [ModelCommand](../Sources/superscribe/ModelCommand.swift), [ModelInstaller](../Sources/SuperscribeKit/ModelInstaller.swift) |
| Shared CLI selectors | Transcriber by default, or isolator/diarizer; conflicting selectors rejected | [BackendTypeOptions](../Sources/superscribe/BackendTypeOptions.swift) |
| Model storage | Transcription backends under `models/transcriber`; isolator and diarizer as sibling kinds | [SuperscribePaths](../Sources/SuperscribeKit/SuperscribePaths.swift) |
| Audio lifetime/cache | File-backed PCM, temporary ownership, ordinary and processed cache variants | [PreparedAudio](../Sources/SuperscribeKit/PreparedAudio.swift), [ConvertedAudioCache](../Sources/SuperscribeKit/ConvertedAudioCache.swift) |
| Rendering | VTT/SRT/JSON/TXT; preserve/trim/interleave policies, word output, cue splitting, and wrapping | [TranscriptRenderer](../Sources/SuperscribeKit/Format/TranscriptRenderer.swift), [Merger](../Sources/SuperscribeKit/Merger.swift) |
| Build resources | Swiftly pin, local whisper xcframework, separately installed Metal compiler, and shipped Metal resource bundle | [Package.swift](../Package.swift), [bootstrap.sh](../_scripts/bootstrap.sh), [MetalLibraryLocation](../Sources/SuperscribeKit/MetalLibraryLocation.swift) |

The package still targets macOS 14 on Apple Silicon. Apple Speech requires macOS 26 at runtime. Earlier proposals for an MLX Whisper backend, automatic backend fallback, cloud ASR, and a macOS 26 package floor are not the implemented design.

## Command reference

The six subcommands are documented once in the README:

- [transcribe](../README.md#transcribe): isolated or mixed inputs, templates, isolation, speech analysis, and ASR.
- [merge](../README.md#merge): render a saved intermediate transcript without inference.
- [run](../README.md#run): transcribe and render, with optional checkpoint retention.
- [model](../README.md#model): choose a model type and manage its supported operations.
- [backend](../README.md#backend): choose a processing type and manage implementations/defaults.
- [cache](../README.md#cache): inspect or remove prepared audio, including isolated variants.

Management selectors do not enable optional pipeline stages. Transcription options choose its backend/model, isolation is opt-in, and mixed-track metadata triggers diarization. Model identifiers such as `htdemucs_ft` and `nemotron-3-diarization` are not additional backend identifiers.

## Extending isolation or diarization

1. Add the implementation behind `VocalIsolator` or `Diarizer`, keeping framework/model calls in the appropriate boundary and lifecycle orchestration testable.
2. Extend `IsolatorBackend` or `DiarizerBackend` with its id, capabilities, and factory. Preserve existing ids and configuration decoding. Check availability and report unsupported environments explicitly.
3. Add the required model descriptors, install validation, and management dispatch. The current model command restricts its backend option to transcription; an alternate auxiliary backend may require extending that routing.
4. Keep processor selection in `PipelineRunner` and injected library configuration. Preserve opt-in activation, source paths, timing, cache separation, and bounded work.
5. Extend tests with stubs and temporary storage. Verify saved defaults remain independent and old configuration files load. Follow the coverage and hardware-test rules in AGENTS.md.
6. Update README examples, architecture diagrams, current guidance, and the append-only decision log together. Bump the product version for the code change using the repository's versioning rules.

These are extension checkpoints; HTDemucs and Nemotron are currently the only isolation and diarization implementations.

## Validation

Use the pinned Swiftly toolchain and the build prerequisites in [Requirements](../README.md#requirements), including the Metal compiler component. A successful Swift compiler version check alone does not establish that Metal shaders can compile.

- [_scripts/test.sh](../_scripts/test.sh) owns the serial strict-concurrency unit invocation.
- [_scripts/coverage.sh](../_scripts/coverage.sh) owns the SuperscribeKit line/region coverage gate and source/binary/profile receipts.
- [Test fixtures](../Tests/superscribeTests/Fixtures/README.md) are repository-owned; ordinary unit tests must not fetch models or depend on the user's cache.
- [AGENTS.md](../AGENTS.md#test-coverage-mandatory) defines opt-in Parakeet, Nemotron, isolation, and Metal integration checks, including their required local assets and inputs.
- [Release packaging](../_scripts/package-release.sh) retains the CLI and resource bundles together; build/signing/publication policy is documented in [AGENTS.md](../AGENTS.md#github-ci).

Report successful local checks separately from checks that need another OS or hardware. macOS 15 cannot exercise all macOS 26 Apple Speech paths; local partial coverage does not satisfy the unchanged full coverage gate. Consult the update log for dated results instead of treating this document as a live test report.

For documentation-only maintenance, validate command options against generated help, examples against source, Mermaid syntax, Markdown fences, local links/anchors, update-log preservation, and whitespace. Do not report unit tests as run when only documentation checks were performed.

## Features still outside the implementation

Automatic track alignment/offsets, YAML sessions, incremental re-transcription, resumable partial output, alternate progress styles, rolling prompts, cloud transcription, and additional auxiliary backends remain future work. See [Future work](podscribe-design.md#future-work); do not document proposed command flags as current options.
