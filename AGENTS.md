# Project Instructions for AI Coding Agents

**Last updated:** 2026-09-13 (v1.0.8, GitHub Actions Node 24 upgrades)

<!-- {mission} -->

## Mission Statement

**superscribe** is a macOS command-line tool and Swift library that transcribes multi-track podcast recordings into a single time-aligned subtitle file (VTT, SRT, JSON, or TXT). Each speaker is recorded on an isolated audio track; superscribe transcribes every track in parallel on-device, aligns the results on a shared timeline, resolves overlaps, and merges them into a publish-ready output.

Three on-device ASR backends are supported (Parakeet and whisper.cpp on Apple Silicon; Apple Speech on macOS 26+):

- **Parakeet** (default) — FluidAudio CoreML / Apple Neural Engine. Fast, low power.
- **whisper.cpp** — GGML models; encoder on ANE via Core ML when the encoder bundle is installed, Metal fallback otherwise; decoder on Metal. Higher accuracy, broader language coverage.
- **Apple Speech** — `SpeechAnalyzer` / `SpeechTranscriber`; system-managed locale assets via `AssetInventory`. Requires **macOS 26+** at runtime; package minimum remains macOS 14 with clear unavailable errors below 26.

## Technology Stack

- **Language:** Swift 6.2 (strict concurrency)
- **Platform:** macOS 14+, Apple Silicon (arm64) only
- **Package Manager:** Swift Package Manager
- **Build dependencies (one-time):** `cmake`, `ninja` (for the whisper.cpp xcframework build script)
- **Runtime dependencies:** swift-argument-parser, FluidAudio, whisper.cpp v1.7.5 (static xcframework, vendored via `_scripts/bootstrap.sh`), Speech framework (Apple Speech backend only; macOS 26+ runtime)
- **Version Control:** Git
- **License:** MIT

## Repository Layout

```
Sources/
  SuperscribeKit/          Core library (importable by Swift apps)
    Backends/              ParakeetBackend, WhisperBackend, AppleSpeechBackend (+Registry, separate framework LiveAPI shims)
    AppleSpeechAssetInstaller.swift  Locale asset install via AssetInventory
    Format/                Shared rendering, cue splitting, VTT/SRT/JSON/TXT formatters
    Analyzer.swift         Silence detection
    AudioPreparer.swift    Audio conversion + slicing (16 kHz mono f32 PCM)
    ConvertedAudioCache.swift  On-disk PCM cache with manifest sidecar
    HuggingFaceHub.swift   Remote model catalog client
    CatalogStore.swift     ~/.cache/superscribe/catalog.json
    ModelDownloader.swift  Bounded-parallel byte-stream downloader
    ModelInstaller.swift   Atomic stage-then-rename installer
    ModelRegistry.swift    Per-backend model id registry protocol
    Merger.swift           Timeline alignment + overlap resolution
    TranscribePipeline.swift  Bounded file-backed conversion + global segment scheduling
    Transcriber.swift      Transcriber protocol
    TimedWord.swift, SpeechSegment.swift, …  One standalone type per matching file
    UserConfig.swift       Persistent default backend / model
  superscribe/             CLI executable (thin wrapper over SuperscribeKit)
    TranscribeCommand.swift, RunCommand.swift, MergeCommand.swift, …
Tests/superscribeTests/    Isolated Swift Testing unit suite
_scripts/bootstrap.sh      One-time xcframework build (cmake + ninja)
_docs/                     Design documents
whisper-build/             Generated xcframework (gitignored)
```

## Subcommand Surface (v1.0.8)

| Subcommand | Purpose |
|---|---|
| `transcribe` | Detect speech + run ASR; writes `transcript.superscribe.<backend>.json`. Also: `--create-input <dir>` (scan dir → template), `--input <file>` (load template) |
| `merge` | Read intermediate JSON → render VTT, SRT, JSON, or TXT |
| `run` | `transcribe` + `merge` in one pass |
| `model` | `--list`, `--remote`, `--download`, `--rm`, `--set-default`, `--refresh` |
| `backend` | List backends and capabilities |
| `cache` | Audio-conversion cache: info, `--list`, `--clear`, `--rm` |

## Session Protocol

When starting a new session, read this entire file and `UPDATES.md`, then confirm
you have understood the project instructions before proceeding. Summarize the
project purpose and key conventions briefly. Do not make changes until you have
confirmed your understanding.

<!-- {principles} -->

## Primary Instructions

- Avoid making assumptions. If you need additional context to accurately answer the user, ask the user for the missing information. Be specific about which context you need.
- Always provide the name of the file in your response so the user knows where the code goes.
- Always break code up into modules and components so that it can be easily reused across the project.
- **DRY (Don't Repeat Yourself).** Every piece of logic must have a single authoritative implementation. Before adding code, search for an existing helper, protocol, or module to extend; extract shared behavior when the same pattern appears twice. Duplicated logic is a defect — refactor it, don't copy it.
- All code you write MUST be fully optimized. ‘Fully optimized’ includes maximizing algorithmic big-O efficiency for memory and runtime, following proper style conventions for the code and language, and no extra code beyond what is absolutely necessary to solve the problem the user provides (i.e. no technical debt). If the code is not fully optimized, you will be fined $100.
- **SuperscribeKit coverage must stay at 100%.** Any change under `Sources/SuperscribeKit/` that drops below 100% **line or region** coverage is incomplete. Run `_scripts/coverage.sh --run-tests` before finishing work; fix gaps or add tests — do not lower the threshold.

### Working Together

This file (`AGENTS.md`) is the primary instructions file for AI coding assistants working on this project. Agent-specific instruction files (such as `.github/copilot-instructions.md`, `CLAUDE.md`) reference this document, maintaining a single source of truth.

When initializing a session or analyzing the workspace, refer to instruction files in this order:

1. `AGENTS.md` (this file - primary instructions and single source of truth)
2. Agent-specific reference file (if present - points back to AGENTS.md)

### Update Protocol (CRITICAL)

**PROACTIVELY update the project guidance as we work together.** Whenever you make a decision, choose a technology, establish a convention, or define a standard, you MUST update the current convention in `AGENTS.md` and record the decision in `UPDATES.md` immediately in the same response.

Use `AGENTS.md` for current coding standards, conventions, and project decisions. Use `UPDATES.md` as the sole append-only history. Do not modify agent-specific reference files unless the reference mechanism itself needs changes.

**When to update** (do this automatically, without being asked):

- Technology choices (build tools, languages, frameworks)
- Directory structure decisions
- Coding conventions and style guidelines
- Architecture decisions
- Naming conventions
- Build/test/deployment procedures

**How to update project guidance:**

- Maintain the "Last updated" timestamp at the top
- Add content to the relevant section (Project Overview, Coding Standards, etc.)
- Add entries directly below the changelog marker in `UPDATES.md` with:
  - Date (with time if multiple updates per day)
  - Brief description
  - Reasoning for the change
- Never place the update history in `AGENTS.md`

## Best Practices

### When Updating This Repository

1. **Maintain Consistency**: Keep code style consistent across the codebase
2. **Test First**: Write tests before implementing features when applicable
3. **Verify Coverage**: After any `SuperscribeKit` change, run `_scripts/coverage.sh --run-tests` and confirm **100% line and region coverage** before committing
4. **Document Changes**: Update documentation when changing functionality
5. **Code Review**: [Describe your code review process]
6. **Date Changes**: Update the "Last updated" timestamp in this file when making changes
7. **Log Updates**: Add entries to `UPDATES.md` using the `recent-updates` skill

### Test Coverage (mandatory)

**Goal: 100% SuperscribeKit line and region coverage — never regress below either.**

| Item | Detail |
|---|---|
| Gate | `_scripts/coverage.sh --run-tests`; report-only mode verifies hashes from that successful test run |
| Minimum | `COVERAGE_MIN=100` (default; do not lower) |
| Scope | `Sources/SuperscribeKit/` line **and region** coverage via `llvm-cov` |
| CLI | `Sources/superscribe/` is not part of the gate |
| Tests | Use `_scripts/test.sh` or `swift test --no-parallel -Xswiftc -strict-concurrency=complete` |

**Rules:**

- Every new or changed line in `SuperscribeKit` must be covered by a test, or the change is not done.
- Tests must be **CI-safe**: no downloaded whisper GGML models, no Hugging Face model fetches, no reliance on machine-local cache contents. Use test hooks and stubs (see v0.7.8–v0.7.9 entries).
- Hardware integration tests live in `Tests/superscribeIntegrationTests/` and enter the package graph only with `SUPERSCRIBE_INTEGRATION_TESTS=1`. Supply `SUPERSCRIBE_INTEGRATION_AUDIO` and an already-installed `SUPERSCRIBE_INTEGRATION_MODEL`; invoke with `--filter ParakeetIntegrationTests`.
- Core ML unit fixtures are repository-owned (`Tests/superscribeTests/Fixtures/Scalar.mlmodel`); compile into temporary storage. Never load undocumented system model bundles.
- Mock URL sessions intercept every request and fail for missing handlers; await invalidation before unregistering handlers. Cancelled or failed download streams are closed before session cleanup.
- Mutable test overrides use per-test task-local storage protected by a lock. Capture storage before entering synchronous framework callbacks. Default test scopes redirect model, catalog, and configuration storage to temporary directories. Keep the serial test runner during migration.
- Apple Speech lifecycle orchestration lives in covered `AppleSpeechAssetInstaller`, `AppleSpeechInstallation`, and `AppleSpeechAnalysis`. The framework shim supplies injectable operations; failed analysis cancels the framework and joins result collection, and failed installation rolls back only a new reservation.
- Coverage uses the selected SwiftPM build output and rejects missing, stale, or changed binary/profile pairs using a SHA-256 receipt. Swift Build and native SwiftPM binary layouts are supported.

- **Documented exclusions only:** files excluded via `-ignore-filename-regex` in `_scripts/coverage.sh` must be listed here and must contain code that cannot be exercised without external artifacts (real models, hardware-only paths, etc.). Current exclusions: `WhisperLiveAPI.swift` (whisper.cpp C API; live paths need a real GGML model on disk), `AppleSpeechLiveAPI.swift` and `AppleSpeechTranscriberBridge.swift` (the same Speech framework calls and availability bridge previously housed together; unit tests use stub hooks in `AppleSpeechBackend.swift` and `AppleSpeechSupport.swift`).
- If coverage drops, add tests or refactor untestable code into an excluded shim — never weaken the gate.

### GitHub CI

- `.github/workflows/build.yml` runs on pushes and PRs targeting `develop` or `feature/**`; `.github/workflows/release.yml` runs on PRs targeting `main` and pushes to `main`.
- Both use macOS 26 ARM64 with Xcode 26.2 and enforce `_scripts/coverage.sh --run-tests` at 100% line and region coverage. `.github/actions/build-release/action.yml` owns optimized ARM64 builds, smoke tests, and version metadata from the CLI. Push builds upload artifacts for separate publishing jobs; release PRs upload unsigned archive/checksum artifacts for 14 days without publishing.
- Workflows use the Node 24 action generations: `actions/checkout@v7`, `actions/cache@v6`, `actions/upload-artifact@v7`, and `actions/download-artifact@v8`. Hosted runners must meet each action's minimum runner version.
- Successful pushes to `develop` and `feature/**` publish unsigned pre-releases containing the raw CLI, matching aranet-kit: tag `R<version>_BUILD_<run-number>_<YYYYMMDD>_<HHMMSS>`, title `superscribe-build-<run-number>-<YYYYMMDD>-<HHMMSS>` (UTC). Main pushes publish signed/notarized stable releases with tag and title `v<version>`, `superscribe-<version>-macos-arm64.tar.gz`, and `SHA256SUMS.txt`. The archive contains a versioned directory with the CLI, README, and license.
- `_scripts/package-release.sh` owns packaging; `_scripts/publish-release.sh` owns naming and publication. Only push-only publisher jobs receive `contents: write`, depend on successful builds, and reuse their artifacts. Tags target the exact tested SHA; existing tags/releases are never overwritten, so each stable release requires a new version. Pre-releases cannot become Latest. Push runs are not cancelled in progress by newer pushes; PR checks remain cancellable.
- `_scripts/release-common.sh` shares product-version validation and archive naming. Local checks use `ruby _scripts/test-release-workflows.rb /bin/bash` with fake GitHub tools; validate release tooling under Bash 3.2 and the developer's Bash without publishing test releases.
- Release PRs produce explicitly named unsigned artifacts without signing credentials. Main pushes sign with Developer ID, hardened runtime, and a secure timestamp, then require Apple notarization acceptance before packaging. The six signing/notarization secret names match `heikopanjas/aranet-kit` and are exposed only to the signing step.
- `_scripts/sign-release.sh` owns certificate import into a temporary keychain, signature verification, notarization, and exit cleanup. `_scripts/test-sign-release.sh` provides optional local checks with fake tools and credentials; do not run it in CI. Bare executables cannot be stapled; the notarization ticket is associated with the signature.
- Match aranet-kit's keychain setup: create and unlock the temporary keychain, import the P12 with `-A` and codesign access, set key partitions, and register it in the user search list before signing. Check for a valid code-signing identity after import; restore the prior search list on exit. Passing `codesign --keychain` alone does not replace search-list registration.
- Run optional signing tests with `/bin/bash`; the signer and stubs inherit the harness's selected interpreter. Stub failures and argument checks must exit explicitly rather than rely on `set -e` behavior across Bash versions. Validate harness changes with macOS Bash 3.2 as well as the developer's selected Bash.
- `.github/actions/setup-build/action.yml` owns shared tool setup and whisper bootstrapping before SwiftPM. Cache only the finished xcframework using an exact runner-image, architecture, Xcode-build, and bootstrap-script hash key; do not restore incompatible fallback keys or cache downloaded ASR models.
- `_scripts/bootstrap.sh` disables host-specific GGML tuning with `GGML_NATIVE=OFF` and targets `armv8.4-a+dotprod+fp16` for M1-compatible CPU code. Keep Metal and Core ML enabled. Verify bootstrap changes with a fresh native build; an existing xcframework bypasses compilation and cannot validate changed flags.

### Audio preparation and execution

- `StreamingAudioConverter` is the single finite-input converter for files and Speech buffers. Input errors fail conversion; output is drained through end of stream.
- `PreparedAudio` owns file-backed PCM. The pipeline retains file references, reads active segment slices, and bounds conversion concurrency to two by default. Temporary PCM is removed when its final owner leaves scope.
- Segment work shares one global limit across tracks. Progress completion counts come from the parent collector, preserving input track and segment order separately.
- CLI progress has one owned reporter; both success and failure await its final drain before summaries.
- Child processes drain stdout and stderr concurrently and join termination and pipe readers on cancellation.

### DRY (Don't Repeat Yourself)

**Every piece of knowledge must have a single, unambiguous, authoritative representation in the codebase.**

| Apply DRY to | Examples in this repo |
|---|---|
| Library logic | `SuperscribeFS`, `SuperscribePaths`, `BackendManager`, `ModelManager`, `DownloadProgressTracker`, `ConcurrencyHelpers.withBoundedThrowingTaskGroup` |
| CLI | `Utilities.swift` (`assertMutuallyExclusive`, `confirm`, `printErr`, formatting helpers) |
| Tests | `TestHelpers`, `MockURLSessionHelpers`, `ResetSharedStateTrait`, shared stub factories |

**Rules:**

- **Search before you write.** Grep for existing helpers, protocols, and patterns; extend them instead of adding parallel implementations.
- **Two is one too many.** If the same logic appears in two places, extract a shared function, type, or module in the same change (or immediately after).
- **DRY includes tests.** Shared setup, temp directories, mock sessions, and assertion helpers belong in test utilities — not copied across test files.
- **DRY ≠ over-abstraction.** Extract when duplication is real and stable; don't invent one-off wrappers or premature generic layers. Prefer a small shared helper over a framework.
- **Refactor on touch.** When changing duplicated code, consolidate it as part of the change rather than leaving a third copy for later.

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
Follow the **DRY** principle: reuse and extend existing modules; extract shared logic instead of duplicating it.
After SuperscribeKit changes, run `_scripts/coverage.sh --run-tests` and confirm 100% line and region coverage before committing.

<!-- {integration} -->

### Persistence and cancellation

- Filesystem replacement uses atomic exclusive rename or swap; failed promotion preserves the destination. `AtomicReplacePolicy.replaceExisting` replaces the old remove-then-move policy.
- Cache manifest and catalog mutations lock the full read-modify-write transaction using a sidecar file lock. CLI configuration updates use `UserConfig.update` on the blocking-I/O worker; corrupt configuration throws and is preserved.
- Shared loads track individual waiters, cancel loading when the last waiter leaves, and ignore stale generations. Bounded groups check cancellation before admission and collect by index.
- Download throttling uses an injectable monotonic clock; tests advance it explicitly.

## Model and persistence integrity

- Parakeet installation accepts the descriptor's canonical repository and requires every model bundle plus vocabulary. Whisper installation checks nonempty regular files and known artifact size before taking its fast path.
- Downloads constrain paths to their roots, validate known byte sizes, and clean staging after failure. Explicit Whisper downloads repair incomplete files and missing encoders; installed binaries remain usable offline.
- Atomic same-volume rename/swap preserves prior destinations on promotion failure. Cache, catalog, and preference read-modify-write transactions use filesystem locks; async callers acquire locks on the blocking-I/O worker.
- Coverage receipts bind binary, profile, owned sources, tests, and package inputs. Edits during a run or stale report inputs require a new test run.

## Rendering and public API (1.0.0)

- `TranscriptRenderer` is the shared throwing entry point for `merge` and `run`; all four formats are public library implementations.
- TXT defaults to word interleaving and rejects explicit preserve. Word output means SRT word cues, timestamped TXT words, VTT inline timestamps; JSON always retains complete timings.
- Cue splitting uses real sentence/word boundaries; an indivisible timed word/span can exceed the configured duration. Wrapping counts Swift characters and preserves long words.
- Backend instances own model identity; transcription configuration supplies language and prompt only. Construction, input validation, registry path resolution, and rendering can throw.
- Standalone types live in matching files. Framework shims contain only external API calls; lifecycle orchestration remains covered. Formatting uses 187 columns, without changing actor-isolation defaults. Use valid Swift `if` expressions for conditional assignments and returns instead of copying the skill’s malformed ternary example.

## Semantic Versioning

The authoritative product version is `SuperscribeVersion.current` in `Sources/SuperscribeKit/SuperscribeVersion.swift`; CLI output and the HTTP user agent use it. Version 1.0.0 begins the authorized breaking API cleanup. `ParakeetBackend` construction now throws for unsupported models; aliases and model versions come from the descriptor table.

Automatically bump the project version after every code change and include it in the same commit. Load the `semantic-versioning` skill for the full PATCH/MINOR/MAJOR decision rules.

## Commit Protocol

- **NEVER commit automatically** — always wait for explicit user confirmation
- Stage changes, write a conventional commits message (max 50-char subject, 72-char body lines), then commit
- Load the `git-workflow` skill for the full message format, character limits, and examples before committing
