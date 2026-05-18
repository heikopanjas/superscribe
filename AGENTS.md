# Project Instructions for AI Coding Agents

**Last updated:** 2026-05-18 (v0.6.0 release)

<!-- {mission} -->

## Mission Statement

**superscribe** is a macOS command-line tool and Swift library that transcribes multi-track podcast recordings into a single time-aligned subtitle file (VTT today; SRT/JSON/TXT planned). Each speaker is recorded on an isolated audio track; superscribe transcribes every track in parallel on-device, aligns the results on a shared timeline, resolves overlaps, and merges them into a publish-ready output.

Two on-device ASR backends are supported, both Apple Silicon only:

- **Parakeet** (default) — FluidAudio CoreML / Apple Neural Engine. Fast, low power.
- **whisper.cpp** — GGML models with Metal GPU acceleration. Higher accuracy, broader language coverage.

## Technology Stack

- **Language:** Swift 6.2 (strict concurrency)
- **Platform:** macOS 14+, Apple Silicon (arm64) only
- **Package Manager:** Swift Package Manager
- **Build dependencies (one-time):** `cmake`, `ninja` (for the whisper.cpp xcframework build script)
- **Runtime dependencies:** swift-argument-parser, FluidAudio, whisper.cpp v1.7.5 (static xcframework, vendored via `_scripts/build-whisper.sh`)
- **Version Control:** Git
- **License:** MIT

## Repository Layout

```
Sources/
  SuperscribeKit/          Core library (importable by Swift apps)
    Backends/              ParakeetBackend, WhisperBackend (+Registry)
    Format/                VTTFormatter
    Analyzer.swift         Silence detection
    AudioPreparer.swift    Audio conversion + slicing (16 kHz mono f32 PCM)
    ConvertedAudioCache.swift  On-disk PCM cache with manifest sidecar
    HuggingFaceHub.swift   Remote model catalog client
    CatalogStore.swift     ~/.cache/superscribe/catalog.json
    ModelDownloader.swift  Bounded-parallel byte-stream downloader
    ModelInstaller.swift   Atomic stage-then-rename installer
    ModelRegistry.swift    Per-backend model id registry protocol
    Merger.swift           Timeline alignment + overlap resolution
    Pipeline.swift         Orchestrates conversion + transcription
    Transcriber.swift      Transcriber protocol
    Types.swift            Core value types
    UserConfig.swift       Persistent default backend / model
  superscribe/             CLI executable (thin wrapper over SuperscribeKit)
    Commands/Options.swift, Subcommands.swift
    SuperscribeCommand.swift
Tests/superscribeTests/    Swift Testing (50 tests)
_scripts/build-whisper.sh  One-time xcframework build (cmake + ninja)
_docs/                     Design documents
whisper-build/             Generated xcframework (gitignored)
```

## Subcommand Surface (v0.6.0)

| Subcommand | Purpose |
|---|---|
| `transcribe` | Detect speech + run ASR; writes `transcript.superscribe.<backend>.json`. Also: `--create-input <dir>` (scan dir → template), `--input <file>` (load template) |
| `merge` | Read intermediate JSON → render formatted output (VTT) |
| `run` | `transcribe` + `merge` in one pass |
| `model` | `--list`, `--remote`, `--download`, `--rm`, `--set-default`, `--refresh` |
| `backends` | List backends and capabilities |
| `cache` | Audio-conversion cache: info, `--list`, `--clear`, `--rm` |

## Session Protocol

When starting a new session, read this entire file and confirm you have
understood the project instructions before proceeding. Summarize the project
purpose and key conventions briefly. Do not make changes until you have
confirmed your understanding.

<!-- {principles} -->

## Primary Instructions

- Avoid making assumptions. If you need additional context to accurately answer the user, ask the user for the missing information. Be specific about which context you need.
- Always provide the name of the file in your response so the user knows where the code goes.
- Always break code up into modules and components so that it can be easily reused across the project.
- All code you write MUST be fully optimized. ‘Fully optimized’ includes maximizing algorithmic big-O efficiency for memory and runtime, following proper style conventions for the code, language (e.g. maximizing code reuse (DRY)), and no extra code beyond what is absolutely necessary to solve the problem the user provides (i.e. no technical debt). If the code is not fully optimized, you will be fined $100.

### Working Together

This file (`AGENTS.md`) is the primary instructions file for AI coding assistants working on this project. Agent-specific instruction files (such as `.github/copilot-instructions.md`, `CLAUDE.md`) reference this document, maintaining a single source of truth.

When initializing a session or analyzing the workspace, refer to instruction files in this order:

1. `AGENTS.md` (this file - primary instructions and single source of truth)
2. Agent-specific reference file (if present - points back to AGENTS.md)

### Update Protocol (CRITICAL)

**PROACTIVELY update this file (`AGENTS.md`) as we work together.** Whenever you make a decision, choose a technology, establish a convention, or define a standard, you MUST update AGENTS.md immediately in the same response.

**Update ONLY this file (`AGENTS.md`)** when coding standards, conventions, or project decisions evolve. Do not modify agent-specific reference files unless the reference mechanism itself needs changes.

**When to update** (do this automatically, without being asked):

- Technology choices (build tools, languages, frameworks)
- Directory structure decisions
- Coding conventions and style guidelines
- Architecture decisions
- Naming conventions
- Build/test/deployment procedures

**How to update AGENTS.md:**

- Maintain the "Last updated" timestamp at the top
- Add content to the relevant section (Project Overview, Coding Standards, etc.)
- Add entries to the "Recent Updates & Decisions" log at the bottom with:
  - Date (with time if multiple updates per day)
  - Brief description
  - Reasoning for the change
- Preserve this structure: title header → timestamp → main instructions → "Recent Updates & Decisions" section

## Best Practices

### When Updating This Repository

1. **Maintain Consistency**: Keep code style consistent across the codebase
2. **Test First**: Write tests before implementing features when applicable
3. **Document Changes**: Update documentation when changing functionality
4. **Code Review**: [Describe your code review process]
5. **Date Changes**: Update the "Last updated" timestamp in this file when making changes
6. **Log Updates**: Add entries to "Recent Updates & Decisions" section below

### Security & Safety

- Never include API keys, tokens, or credentials in code
- Always require explicit human confirmation before commits
- Maintain conventional commit message standards
- Keep change history transparent through commit messages
- [Add project-specific security guidelines]

<!-- {languages} -->

## Swift Coding Standards

Load the `swift-coding-conventions` skill before writing, reviewing, or refactoring Swift code.
Load the `swift-build-commands` skill when building or running the project.
Load the `swift-testing-pro` skill when writing, reviewing, or refactoring tests (Swift Testing or XCTest).

<!-- {integration} -->

## Semantic Versioning

Automatically bump the project version after every code change and include it in the same commit. Load the `semantic-versioning` skill for the full PATCH/MINOR/MAJOR decision rules.

## Commit Protocol

- **NEVER commit automatically** — always wait for explicit user confirmation
- Stage changes, write a conventional commits message (max 50-char subject, 72-char body lines), then commit
- Load the `git-workflow` skill for the full message format, character limits, and examples before committing

---

<!-- {changelog} -->

## Recent Updates & Decisions

### 2026-05-18 (v0.6.0 polish + README/LICENSE)

- **README.md added.** Full user-facing docs: requirements, quick start, backends, model management, every subcommand with option tables, `--create-input`/`--input` workflow, intermediate JSON format, xcframework build instructions, project structure. No emojis per user preference.
- **LICENSE added.** MIT, copyright 2026 Heiko Panjas.
- **Special-token leak fix (WhisperBackend).** `extractTimedWords` previously only filtered tokens with negative ids, which let whisper's `[_BEG_]` (50363) and `[_TT_N]` (50364–50563) bracket tokens leak into transcribed word text. Now also skips any token whose text starts with `"[_"`.
- **Default transcript filename includes backend.** `--output` default changed from `transcript.superscribe.json` to `transcript.superscribe.<backend>.json` so parakeet and whisper.cpp results don't overwrite each other. User-supplied `--output` still wins.
- **`transcribe --create-input <dir>`.** Stand-alone option that scans a directory for audio files (`mp3 wav m4a aac flac ogg mp4 mov caf opus`), sorts with `localizedStandardCompare`, and writes `tracks.superscribe.json` to the *current working directory* with `speaker-<n>` → cwd-relative path mappings. Mutually exclusive with `--track` and `--input`.
- **`transcribe --input <file>`.** Loads a `[String: String]` track-mapping JSON (as produced by `--create-input`) and resolves filenames relative to cwd. Mutually exclusive with `--track`.
- **Pipeline trims empties.** `IntermediateTranscript` now drops segments where `words.isEmpty` (silence-analyzer false positives — breath, FX, music above dB threshold) and drops tracks where `segments.isEmpty` (FX/noise tracks).
- **Committed as `f6b76fd`.** 24 files, 943 insertions, 388 deletions.

### 2026-05-18 (cache subcommand)

- **`cache` subcommand added (v0.6.0).** New `superscribe cache` CLI subcommand with four operations: default (print location + entry count + total size), `--list` (one line per entry: digest, size, age), `--clear [--yes]` (delete entire cache directory with `[y/N]` confirmation), `--rm <path>` (delete the entry for a specific source file using current metadata). Both backends use `.asr16kMono` (`f32-16000-1`), so there is exactly one cache entry per source file and no `--backend` disambiguation is needed. No library changes — all required API (`defaultRoot`, `key(for:targetFormat:)`, `lookup`, `cacheURL`) was already public on `ConvertedAudioCache`. `formatAge` private helper added for human-readable relative timestamps. `CacheCommand` follows the same `validate()` mutual-exclusivity and `[y/N]` confirmation patterns as `ModelCommand`.

### 2026-05-18 (whisper.cpp migration)

- **Whisper backend: migrated to whisper.cpp static xcframework (v0.5.0).** Replaced the `argmax-oss-swift` Swift package dependency with a static arm64 xcframework built from whisper.cpp v1.7.5 source. The xcframework is built once by `_scripts/build-whisper.sh` (requires cmake + ninja), output to `whisper-build/whisper.xcframework` (gitignored), and consumed via SPM `.binaryTarget(path:)`. `SuperscribeKit` gains `linkerSettings` for `Metal`, `MetalKit`, `Accelerate`, and `c++`. This pins the whisper.cpp C API version the user runs against regardless of their system state — API breakage is only ever visible when we deliberately upgrade the xcframework. Drops 6 transitive Swift deps (swift-transformers, swift-jinja, yyjson, swift-crypto, swift-asn1, swift-collections).
- **Model catalog changed.** Whisper models are now single GGML `.bin` files from `ggerganov/whisper.cpp` on HuggingFace. `defaultModelId = "large-v3-turbo"` (hyphen, not underscore). Install path changed from `~/Documents/huggingface/.../openai_whisper-<id>/` (old convention) to `~/Library/Caches/superscribe/whisper/<id>.bin`. Old model folders are orphaned; user can delete manually.
- **ModelInstaller single-file support.** `isInstalled(at:backend:)` for `.whisper` now checks for a regular file (not a directory + `.mlmodelc`). Staging uses a sibling `.bin.staging-<uuid>` file path (not a staging directory). `ModelDownloader.downloadFile(model:into:onProgress:)` added for single-file downloads.
- **WhisperBridge.swift deleted.** Bridging helpers (`extractWords`, `WKWord`) are no longer needed; whisper.cpp token data is read directly via C API in `WhisperBackend.extractTimedWords`.
- **Build integration.** `_scripts/build-whisper.sh` handles: prerequisite check (cmake/ninja), download of v1.7.5 tarball, cmake configure (arm64, Metal embedded, no examples/tests), ninja build, libtool combine of all `libggml*.a` + `libwhisper.a`, xcodebuild xcframework creation, module.modulemap injection.

### 2026-05-02 (audio cache)

- **Audio converter: live progress + persistent cache (v0.4.0).** `AudioPreparer` now reports streaming `ConversionProgress` (source frames consumed, fraction 0–1) via an optional `(@Sendable) -> Void` callback; the converter loop reads the source in ~1 s chunks and feeds them to `AVAudioConverter` instead of the previous one-shot whole-file convert. New `ConvertedAudioCache` (`Sources/SuperscribeKit/ConvertedAudioCache.swift`) persists already-converted PCM as WAV under `~/.cache/superscribe/audio/<sha256>.wav`. Cache key = `sha256(absPath │ size │ mtime_ns │ formatKey)` where `formatKey` = `"f32-<rate>-<channels>"` derived from `BackendCapabilities.requiredAudioFormat` — future backends with different requirements get separate entries automatically. Writes are atomic (sibling `.staging-<uuid>` then `moveItem`). On a cache hit, the WAV reads back through the existing fast path with zero re-conversion. CLI: `transcribe`/`run` enable the cache by default and now print a throttled (~10 Hz) `Converting <name> [N%]` line per track on stderr; new `--no-cache` flag opts out. Verified end-to-end on a 30-min mp4: cold run writes a 321 MB WAV; warm run skips conversion entirely.

### 2026-05-02 (even later)

- **Model installer + lifecycle (v0.3.0).** Superscribe now owns all model downloads end-to-end. New `ModelDownloader` (URLSession byte-stream, ≤4 parallel files, 64 KiB write batches, ~10 Hz throttled progress) and `ModelInstaller` (atomic stage-then-rename via `<finalDir>.staging-<uuid>`, quota-aware preflight via `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`, single global serial install lock). Backends now load-from-disk only — `WhisperBackend` loads a GGML `.bin` via `whisper_init_from_file_with_params`, `ParakeetBackend` uses `AsrModels.load(from:)`; both throw `ModelInstallationError.modelNotInstalled` if the local folder is missing. `transcribe` and `run` auto-install the resolved model with a live stderr progress line before transcribing. `models` gains `--download <id>` (idempotent, prints `Already installed at …` or installs with progress) and `--rm <id>` (interactive `[y/N]` confirmation, `--yes` to bypass).
- **Parakeet on-disk path corrected.** `ParakeetBackend.fluidAudioCacheDirectory()` was scanning `~/.cache/fluidaudio/Models` (FluidAudio's TTS path) — the actual ASR cache is `~/Library/Application Support/FluidAudio/Models/<folderName>`. Also: FluidAudio's `Repo.folderName` strips the `-coreml` suffix (e.g. HF repo `parakeet-tdt-0.6b-v3-coreml` → folder `parakeet-tdt-0.6b-v3`) and `parakeet-ja` differs from its HF repo name `parakeet-0.6b-ja-coreml`. Introduced a single `ParakeetBackend.ModelDescriptor` table linking short id ↔ HF repo bare name ↔ on-disk folder name; `installPath` and `installFolderName` now match FluidAudio's convention exactly so previously-downloaded models are detected without migration. `installedModels` requires a `.mlmodelc` bundle to count as installed.

### 2026-05-02 (later)

- **Models command rework (v0.2.0).** Hugging Face Hub is now the authoritative model catalog. New `ModelRegistry` protocol replaces per-backend `availableModels` enums; each backend exposes `defaultModelId`, `remoteModels()`, and `installedModels()`. Added `HuggingFaceHub` URLSession client (tolerates fractional-second ISO 8601 dates) and `CatalogStore` persisting to `~/.cache/superscribe/catalog.json` with schema `{ version, entries: { backend → { fetchedAt, models } } }`. `models` rewritten as `AsyncParsableCommand` with flags `--list` (implicit), `--remote`, `--refresh`, `--set-default <id>`, `--backend`, `--json`. `backends --capabilities` trimmed to a one-screen summary that points at `models --list --remote`. Decisions locked in for future work: no partial downloads (atomic stage-then-rename), and download commands must show live progress.

### 2026-05-02

- **Library extraction.** Split single `superscribe` executable into `SuperscribeKit` library target + thin `superscribe` CLI executable. Core logic (types, analyzer, merger, formatters, pipeline, backends) lives in `SuperscribeKit`; CLI imports it plus `ArgumentParser`. Tests depend on `SuperscribeKit`. Reasoning: enables framework-based consumption beyond CLI (Swift apps, third-party integrations).
- **Backend enum cleanup.** Renamed `Backend.mlx` → `.parakeet`, dropped `.auto` and `.openai`. Remaining cases: `.parakeet` (default, FluidAudio), `.whisper` (whisper.cpp), `.appleSpeech` (reserved, macOS 26).

### 2026-05-01

- **Backend research recorded.** MLX Whisper does not exist for Swift; Phase 3 spike concluded. Recommended MVP backend is FluidAudio (Parakeet TDT v3, CoreML/ANE, Apache-2.0). whisper.cpp (GGML) is the planned secondary backend; Apple `SpeechAnalyzer` is reserved for when a macOS 26 deployment floor is acceptable. Findings captured in [_docs/podscribe-design.md](_docs/podscribe-design.md) Appendix A and [_docs/superscribe-mvp-implementation-plan.md](_docs/superscribe-mvp-implementation-plan.md). Project paused pending user decision on backend; state frozen in `/memories/repo/superscribe-state.md`.
- Reference the `swift-testing-pro` skill in the Swift Coding Standards section so it is loaded for any test-related work. Reasoning: the skill was added to the project and should be discoverable from AGENTS.md.

### 2025-10-05

- Initial AGENTS.md setup
- Established core coding standards and conventions
- Created agent-specific reference files
- Defined repository structure and governance principles
