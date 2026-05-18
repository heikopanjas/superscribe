# Superscribe MVP — Implementation Plan

**Last updated:** 2026-05-01
**Status:** Draft
**Owner:** TBD
**Related:** [podscribe-design.md](podscribe-design.md)

## Goal

Smallest vertical slice that turns N isolated speaker tracks into one chronological, speaker-attributed **VTT** transcript using a single on-device ASR backend. CLI name `superscribe` everywhere.

## Non-Goals (deferred)

- Whisper.cpp / Speech.framework / OpenAI backends
- SRT / JSON / TXT output formats
- YAML session manifest
- Overlap policies `trim` / `interleave`
- All design-doc "Open Issues" (track alignment, incremental re-transcription, progress reporting, error recovery, rolling prompt, final naming)

## Architectural Decisions

- **Backend:** see *Backend Decision* below — MLX dropped after spike. Other backends stubbed behind a `Transcriber` protocol so adding them is purely additive.
- **Overlap policy:** `preserve` only — VTT supports concurrent cues.
- **Format:** VTT only — formatter interface ready for SRT/JSON/TXT later.
- **Naming:** `superscribe` everywhere; renaming the design doc is a follow-up cleanup.
- **Concurrency:** Tracks analysed in parallel; per-backend fan-out for transcription, bounded by a configurable in-flight limit.
- **Module layout:** Two targets — `SuperscribeKit` (library) and `superscribe` (thin CLI executable). The library contains all core logic (types, analyzer, merger, formatters, backends, pipeline) and is independently consumable. The CLI imports `SuperscribeKit` + `ArgumentParser` for command-line parsing only. Tests depend on `SuperscribeKit`.

## Backend Decision (2026-05-01)

**Spike outcome:** there is no Swift port of MLX Whisper. `mlx-swift` is a low-level array/NN library; `mlx-swift-examples` and `mlx-swift-lm` cover MNIST / LLM / VLM / StableDiffusion but not Whisper. MLX Whisper exists only in the Python `mlx-examples` repo. Porting it is out of scope for the MVP.

Viable on-device candidates surveyed (April 2026):

| Backend | Model | License | Min macOS | Notes |
| --- | --- | --- | --- | --- |
| **FluidAudio** (FluidInference) | Parakeet TDT v3 (0.6B, 25 EU langs) / v2 (English) on CoreML/ANE | Apache-2.0 | 14 | ~190× RT on M4 Pro; word timestamps; `AsrManager.transcribe([Float])` / `transcribe(AVAudioPCMBuffer)`; ANE-only → cheap parallelism across speaker tracks; bundled `AudioConverter` for resample to 16 kHz mono; very active (v0.14.3, late Apr 2026). |
| **WhisperKit** (`argmaxinc/argmax-oss-swift`) | OpenAI Whisper large-v3 CoreML | MIT | 14 | Mature; prompt tokens; word timestamps; slower than Parakeet on ANE but often more robust on noisy / accented audio. Same package now also ships SpeakerKit + TTSKit. |
| **Apple `SpeechAnalyzer` / `SpeechTranscriber`** | Apple-managed assets via `AssetInventory` | system | **26** | Native, zero-dep, `Sendable` actor, `analyzeSequence(from: AVAudioFile)`, word-level timing via `Result.attributeOptions`. Requires bumping deployment target to macOS 26 — not acceptable for MVP. |

**MVP choice:** **FluidAudio with Parakeet TDT v3** as the default backend.

- ANE inference frees the GPU and lets us transcribe N speaker tracks largely in parallel without contention.
- Word timestamps are first-class (needed by the merger).
- Diarization is irrelevant for us (one track = one speaker), so we use only FluidAudio's ASR slice.
- macOS 14 deployment target stays.

**Backend enum:** rename `.mlx` → `.parakeet` (default). Keep `.whisper` (WhisperKit) as a planned secondary, `.appleSpeech` reserved for when we accept a macOS 26 floor. `.openai` deferred.

## Open Questions

1. ~~MLX Whisper API surface~~ — **Resolved 2026-05-01:** no Swift MLX Whisper exists; switching to FluidAudio/Parakeet (see *Backend Decision*).
2. **Per-track ASR concurrency** — confirm empirically how many concurrent `AsrManager.transcribe` calls maximise ANE throughput on M-series. Default to 2 until measured.
3. **Long-segment chunking** — Parakeet TDT v3 has a practical chunk size; FluidAudio exposes `transcribeLong` for batch. Decide whether the Analyzer's per-segment slices are short enough to feed `transcribe` directly or whether to delegate long-form handling to the backend.

---

## Phase 0 — Package Restructuring

**Depends on:** nothing.

- [ ] Edit [Package.swift](../Package.swift): set `platforms: [.macOS(.v14)]` (FluidAudio requirement).
- [ ] Add `https://github.com/FluidInference/FluidAudio` (`from: 0.14.3`) as a package dependency; wire `FluidAudio` product into the `superscribe` executable target.
- [ ] Add `superscribeTests` test target using Swift Testing.
- [ ] Create directory skeleton inside `Sources/superscribe/`: `Commands/`, `Backends/`, `Format/`. Create `Tests/superscribeTests/`.

**Verification:** `swift build` succeeds; `swift test` runs the empty test target.

---

## Phase 1 — Core Types + CLI Skeleton

**Depends on:** Phase 0.

- [ ] `Sources/SuperscribeKit/Types.swift` — `TimedWord`, `SpeechSegment`, `TranscriptionResult`, `TranscriptionConfig`, `AttributedSegment`, `MergedSegment`, enums `Backend`, `OverlapPolicy`, `OutputFormat`. All `Sendable`; persisted ones `Codable`.
- [ ] `Sources/SuperscribeKit/IntermediateTranscript.swift` — Codable model for `.superscribe.json` (`version`, `session`, `created`, `tracks`, `metadata`).
- [ ] `Sources/superscribe/SuperscribeCommand.swift` — `@main AsyncParsableCommand` with `transcribe` / `merge` / `run` subcommands stubbed (print "not implemented").
- [ ] `Sources/superscribe/Commands/Options.swift` — shared option groups `TranscribeOptions` and `MergeOptions` per design doc.

**Verification:** `swift run superscribe --help` lists all three subcommands; `swift run superscribe transcribe --help` shows all flags.

---

## Phase 2 — Analyzer (Silence Detection)

**Depends on:** Phase 1. *Can run in parallel with Phase 3.*

- [ ] `Sources/SuperscribeKit/Analyzer.swift`:
  - [ ] `AnalyzerConfig` struct with defaults (−40 dB, 0.5 s min silence, 0.15 s padding, 1024-sample window).
  - [ ] `Analyzer.detectSpeech(in: URL) throws -> [SpeechSegment]`.
  - [ ] PCM read via `AVAudioFile`; convert to mono Float32 if needed.
  - [ ] Sliding-window RMS → dB; state machine (silence/speech) at threshold.
  - [ ] Merge gaps shorter than `minSilenceDuration`; apply padding; clamp to file duration; drop segments < 100 ms.
- [ ] `Tests/superscribeTests/AnalyzerTests.swift` — synthesised in-test wav fixtures:
  - [ ] Pure silence → empty result.
  - [ ] Constant tone → one segment spanning file.
  - [ ] Tone-silence-tone → two segments with correct boundaries.
  - [ ] Sub-100 ms blip → dropped.
  - [ ] Padding extends boundaries correctly.

**Verification:** `swift test --filter AnalyzerTests` passes.

---

## Phase 3 — Parakeet (FluidAudio) Backend

**Depends on:** Phase 1. *Can run in parallel with Phase 2.*

- [ ] `Sources/SuperscribeKit/Transcriber.swift` — `Transcriber` protocol + `selectBackend(preferred:)` returning the Parakeet backend; other cases `fatalError` with TODO.
- [ ] `Sources/SuperscribeKit/Backends/ParakeetBackend.swift`:
  - [ ] Conform to `Transcriber`; `static var isAvailable` checks Apple Silicon at runtime.
  - [ ] Lazy load `AsrModels.downloadAndLoad(version: .v3)` once per process; cache `AsrManager` behind an actor.
  - [ ] Models cached to FluidAudio's default location (`~/.cache/fluidaudio/Models/...`); progress surfaced on stderr.
  - [ ] `transcribe(file:segment:config:)` slices PCM for the segment, calls `AsrManager.transcribe(samples)`, maps result + token timings to `TranscriptionResult` with `TimedWord` array.
  - [ ] Honor `config.language` (map to Parakeet locale tag) and `config.prompt` if FluidAudio exposes a context/prompt hook (otherwise log a one-time warning).
- [ ] `Tests/superscribeTests/ParakeetBackendTests.swift`:
  - [ ] Skip (`withKnownIssue` / trait) when `ParakeetBackend.isAvailable == false` or model assets are absent.
  - [ ] Smoke test on a tiny committed clip (≤ 100 KB): assert non-empty result; word timestamps within segment bounds. Don't assert exact text.

**Verification:** `swift test --filter ParakeetBackendTests` passes locally on Apple Silicon.

---

## Phase 4 — Transcribe Pipeline + `transcribe` Subcommand

**Depends on:** Phase 2 + Phase 3.

- [ ] `Sources/SuperscribeKit/Pipeline.swift` — `TranscribePipeline.run(session:) async throws -> IntermediateTranscript`:
  - [ ] Phase 1: `withThrowingTaskGroup` over tracks → `[(speaker, [SpeechSegment])]`.
  - [ ] Phase 2: bounded fan-out over segments calling the backend; collect into `IntermediateTranscript`.
  - [ ] Concurrency limit configurable (default 2 for ANE).
- [ ] `Sources/superscribe/Commands/TranscribeCommand.swift`:
  - [ ] Parse `--track name=path` flags into a session.
  - [ ] Run pipeline, write `.superscribe.json` to `--output`.
- [ ] `Tests/superscribeTests/PipelineTests.swift`:
  - [ ] `MockBackend` returning deterministic results per segment (no model needed, CI-friendly).
  - [ ] Two tiny synthesised tracks → run pipeline → assert `IntermediateTranscript` round-trips through JSON and preserves track/speaker structure.

**Verification:** `swift run superscribe transcribe --track Alice=a.wav --track Bob=b.wav --output out.superscribe.json` produces a valid JSON file.

---

## Phase 5 — Merger (Preserve Only) + VTT Formatter

**Depends on:** Phase 1. *Can run in parallel with Phases 2–4.*

- [ ] `Sources/SuperscribeKit/Merger.swift`:
  - [ ] `flatten` → `resolveOverlaps(policy: .preserve)` (no-op for MVP) → `insertBreaks` → `coalesce` → `[MergedSegment]`.
  - [ ] `trim` and `interleave` policies stubbed with `fatalError("not implemented")` and TODO note.
- [ ] `Sources/SuperscribeKit/Format/VTTFormatter.swift`:
  - [ ] Emit `WEBVTT` header + cues with `<v Speaker>` voice tags.
  - [ ] Timestamps `MM:SS.mmm` (or `HH:MM:SS.mmm` if ≥ 1 h).
  - [ ] Optional inline word-level timestamps via `--include-words`.
- [ ] `Tests/superscribeTests/MergerTests.swift`:
  - [ ] Two non-overlapping speakers → correct chronological order.
  - [ ] Same speaker, two adjacent segments under `maxGap` → coalesced.
  - [ ] Gap ≥ `gapThreshold` → paragraph break preserved (no coalesce).
- [ ] `Tests/superscribeTests/VTTFormatterTests.swift` — golden-file comparison on a small fixture.

**Verification:** `swift test --filter "MergerTests|VTTFormatterTests"` passes.

---

## Phase 6 — `merge` and `run` Subcommands

**Depends on:** Phase 4 + Phase 5.

- [ ] `Sources/superscribe/Commands/MergeCommand.swift` — read intermediate JSON, run merger, write VTT to `--output` or stdout.
- [ ] `Sources/superscribe/Commands/RunCommand.swift` — compose transcribe + merge in one call; `--keep-intermediate` writes the JSON, default discards.
- [ ] `Tests/superscribeTests/EndToEndTests.swift` — two tiny tracks → `run` with `MockBackend` → assert VTT contains both speakers in chronological order with `<v Speaker>` tags.

**Verification:** `swift run superscribe run --track Alice=a.wav --track Bob=b.wav --output ep.vtt` produces a valid VTT file.

---

## Cross-Cutting Tasks

- [ ] Bump package version in [Package.swift](../Package.swift) per `semantic-versioning` skill on each phase commit.
- [ ] Update [AGENTS.md](../AGENTS.md) "Recent Updates & Decisions" log when architecture decisions change.
- [ ] Manual smoke test on a real two-track recording before declaring MVP complete; eyeball VTT in a player.

## Relevant Files

- [Package.swift](../Package.swift) — add MLX deps, set macOS 14 platform, add test target.
- [Sources/superscribe/superscribe.swift](../Sources/superscribe/superscribe.swift) — current SPM stub; replaced by `SuperscribeCommand.swift` in Phase 1.
- [_docs/podscribe-design.md](podscribe-design.md) — source of truth for types, algorithms, CLI flags. Rename `podscribe` → `superscribe` once MVP lands.
- New: `Sources/superscribe/{Types,IntermediateTranscript,Analyzer,Transcriber,ModelManager,Pipeline,Merger,SuperscribeCommand}.swift`, `Sources/superscribe/Commands/**`, `Sources/SuperscribeKit/Backends/**`, `Sources/superscribe/Format/**`, `Tests/superscribeTests/**`.
