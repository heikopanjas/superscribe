# Recent Updates & Decisions

This file is the append-only log of project decisions and notable changes, maintained by coding agents following the `recent-updates` skill. Everything below the marker line is user-owned history: slopctl never overwrites it during init or merge.

<!-- {changelog} -->

### 2026-09-13 (v1.0.8, 17:38 github actions node 24 upgrades)

- upgraded checkout, cache, artifact upload, and artifact download to their current Node 24 action generations
- kept the existing workflow inputs and artifact flow; GitHub-hosted runners exceed the actions' minimum runner versions
- rationale: remove Node 20 runtime and `punycode` deprecation warnings from build and release jobs
- version bump: 1.0.7 to 1.0.8 (PATCH - ci dependency maintenance with no public api changes)

### 2026-09-13 (v1.0.7, decision log consolidation)

- moved the complete decision history to `UPDATES.md` and removed the duplicate log from `AGENTS.md`
- set `UPDATES.md` as the sole append-only history; `AGENTS.md` now holds current conventions
- removed the `GitHub Actions` and `Migration to 1.0` sections from `README.md`
- rationale: keep one authoritative history and remove outdated readme material

### 2026-09-12 (v1.0.7, 22:09 github release publication)

- adopted aranet-kit's exact pre-release and stable naming/tagging conventions, with unsigned pre-releases on develop and feature pushes and signed/notarized stable releases on main
- matched raw pre-release assets and versioned stable archives with readme, license, and sha256 checksums; shared optimized builds and reused artifacts in separate push-only publishing jobs
- pinned tags to tested commits, rejected existing tags, and kept pre-releases out of latest; prs remain validation-only
- rationale: publish successful builds as github releases without changing the verified signing setup or exposing publication credentials to pr builds
- version bump: 1.0.6 to 1.0.7 (PATCH - release tooling, no public API changes)

### 2026-09-12 (v1.0.6, 21:27 signing keychain registration)

- matched aranet-kit's p12 access settings and registered the temporary keychain in the user's search list before signing; cleanup restores the original search list
- added valid-identity preflight and signing diagnostics; local-only checks cover registration, missing identities, and restoration
- rationale: repair the omitted keychain setup from the reference workflow after the main release reported no identity found
- version bump: 1.0.5 to 1.0.6 (PATCH - release signing setup fix)

### 2026-09-12 (v1.0.5, 21:11 optional local signing tests)

- removed signing-orchestration tests from both ci workflows at the user's request; retained the corrected harness for optional local checks
- rationale: keep simulated signing checks outside ci while main pushes still perform and verify real signing and notarization

### 2026-09-12 (v1.0.5, 21:09 bash-compatible signing tests)

- made signing-stub failures explicit and kept signer/stub processes on the harness's selected bash; ci invokes `/bin/bash`
- rationale: eliminate bash 3.2 versus 5.3 errexit differences while retaining credential-free checks that failed signing stops packaging and cleans temporary credentials
- version bump: 1.0.4 to 1.0.5 (PATCH - test-harness compatibility fix)

### 2026-09-12 (v1.0.4, 20:59 signed release artifacts)

- added developer id signing and notarization on main pushes using the existing six aranet-kit secret names; pr artifacts remain explicitly unsigned
- isolated credentials to the signing step and a temporary keychain with exit cleanup; require signature verification and accepted notarization before packaging
- added credential-free orchestration tests for failure handling, notarization status, and cleanup
- rationale: follow the reference repository's pr/main split and distribute verifiable artifacts without exposing signing credentials to pr builds
- version bump: 1.0.3 to 1.0.4 (PATCH - release tooling without public api changes)

### 2026-09-12 (v1.0.3, 20:37 portable whisper cpu build)

- disabled ggml native cpu probing and selected `armv8.4-a+dotprod+fp16`, preserving metal and core ml
- rationale: fix the hosted runner's contradictory i8mm settings and keep release binaries compatible with the m1 cpu baseline
- require fresh native compilation when verifying bootstrap changes; script changes invalidate the exact ci cache key
- version bump: 1.0.2 to 1.0.3 (PATCH - native dependency build fix)

### 2026-09-12 (v1.0.2, 20:10 github ci workflows)

- added build checks for pushes and prs targeting `develop` or `feature/**`, and release validation for prs targeting `main`
- shared macos 26 arm64 and xcode 26.2 setup installs missing tools and bootstraps whisper before swiftpm, caching only the finished xcframework by exact image, architecture, toolchain, and script hash
- both workflows enforce 100 percent line and region coverage; release validation builds and smoke-tests the optimized cli and retains a tar artifact for 14 days
- rationale: validate on compatible apple hardware, reuse the combined metal/core ml build, and provide reviewable release candidates without publishing from prs
- version bump: 1.0.1 to 1.0.2 (PATCH - ci tooling with no public api changes)

### 2026-09-12 (v1.0.1, 19:41 bootstrap script rename)

- renamed the whisper xcframework build entry point to `_scripts/bootstrap.sh`
- updated build documentation and generated-artifact metadata to use the new path
- rationale: the bootstrap name describes the script's role in preparing the local binary dependency
- version bump: 1.0.0 to 1.0.1 (PATCH - documented build tooling change)

### 2026-09-12 (v1.0.0, 19:14 final unit and sanitizer verification)

- consolidated duplicate counters, Parakeet session stubs, ZIP builders, and audio fixtures
- replaced conditional assignments and returns with valid Swift if expressions and completed formatter cleanup
- backend loading now rejects incomplete local Parakeet artifacts before FluidAudio can attempt model resolution
- cancellation cleanup no longer relies on which Speech result branch finishes first; all children are joined
- validation: 455 tests in 98 suites pass; SuperscribeKit covers all 4908 lines and 1959 regions; formatter lint and strict-concurrency compilation pass
- focused Thread Sanitizer verification passes 34 tests in 13 suites; all four CLI output formats match golden fixtures
- coverage provenance rejects added source files and mismatched profiles, then passes after inputs are restored
- no commits were created; hardware inference still needs the requested explicit audio fixture and installed model


### 2026-09-12 (v1.0.0, 19:02 regression verification and resource cleanup)

- validated complete parakeet component layouts and canonical repository identity, plus known whisper binary sizes; partial installs are repaired through staging
- closed failed download streams before awaiting URLSession invalidation, including HTTP errors before byte iteration
- restored chronological cue order after subtitle splitting and word expansion; golden fixtures cover all four CLI formats
- bounded preparation and cancellation tests join every worker and verify temporary PCM removal; forced segment completion order is 2, 0, 1
- registered global whisper logging callbacks once before context creation
- validation: strict-concurrency unit suite and 100 percent line/region coverage passed; 34 focused Thread Sanitizer tests passed without race reports
- hardware inference remains pending an explicit local audio fixture and installed model; unit coverage does not establish hardware behavior


### 2026-09-12 (v1.0.0, 18:40 output formats and API cleanup)

- implemented preserve, trim, and stable word interleaving with sentence/word cue splitting and Unicode wrapping
- added shared throwing VTT, SRT, TXT, and deterministic versioned JSON rendering for both CLI paths
- backend instances now own model identity; removed redundant per-call model selection
- split standalone types and test suites into matching files and removed force unwraps
- retained the same external framework coverage boundaries under accurately named shim files; error descriptions are now covered code
- rationale: output behavior and validation must agree between the CLI and public library


### 2026-09-12 (v1.0.0, 17:47 bounded audio and lifecycle work)

- consolidated finite audio conversion and introduced file-backed prepared PCM with scoped temporary ownership
- scheduled segment jobs globally and counted completion in the parent collector while preserving input order
- replaced queued global CLI progress with an owned reporter that drains on both outcomes
- added cancellation-aware FIFO model lifecycle coordination and retained encoders shared by quantized variants
- confined model paths component by component and drained archive subprocess diagnostics during execution
- added early library input validation and shared absolute/relative track-mapping loading
- validation remains in progress; the new audio path requires regression and coverage verification


### 2026-09-12 (v1.0.0, 17:21 atomic persistence and cancellation)

- replaced remove-then-move publication with exclusive rename and atomic swap
- locked cache and catalog transactions across instances and processes; scoped WAV writer lifetime before publication
- configuration loading now throws for corruption; CLI updates preserve unrelated fields under a filesystem lock on a blocking worker
- the installed-model registry contract is async and now includes Apple Speech
- shared loading cancels individual waiters independently and protects retries from stale completion
- bounded groups check cancellation before submitting work, collect indexed results, and discard Void completions without an array
- progress uses a monotonic clock with deterministic tests instead of sleeps
- validation: the strict-concurrency coverage gate again passed at 100 percent line and region coverage


### 2026-09-12 (v1.0.0, 17:12 validated parakeet and whisper ownership)

- parakeet construction now throws for unknown models, with aliases and model versions defined by one descriptor table
- unsupported repositories are omitted from the advertised parakeet catalog
- whisper strings stay alive during C inference; nil language enables detection and subsecond audio is padded with tail words clipped
- an owned serial worker handles whisper context creation, inference, and destruction, with cancellation wired to the C abort callback
- CLI output and HTTP requests use the same product version constant
- version bump: 0.8.1 to 1.0.0 (MAJOR - validated construction breaks the public initializer contract)


### 2026-09-12 (v0.8.1, 17:05 covered speech lifecycle)

- moved locale resolution, reservation rollback, installation progress ownership, and analysis/result joining into covered components
- reservation false now means already reserved; only newly acquired reservations are released after failure
- canonical locale identities flow into installation and returned markers
- default tests use temporary model, catalog, and configuration storage
- focused thread sanitizer checks passed for scoped dependency isolation and bounded test concurrency
- rationale: framework cleanup must finish before operations return, and unit tests must not modify user assets


### 2026-09-12 (v0.8.1, 16:59 test scopes and coverage provenance)

- mutable test overrides now use independent task-local storage with synchronized reads and writes
- audio converter callbacks explicitly capture their dependency storage
- concurrency tests use a shared entry barrier and await cleanup instead of sleeps and detached cleanup tasks
- coverage binds the profile to its actual SwiftPM binary and verifies both hashes before reporting
- configuration saving creates the resolved configuration parent, including nested test overrides
- rationale: prevent overlapping tests from altering each other's dependencies and prevent stale build outputs from satisfying the coverage gate


### 2026-09-12 (v0.8.1, test isolation foundation)

- moved conditional Parakeet inference out of the default suite into an explicitly enabled integration target
- replaced the undocumented Maps model dependency with a repository-owned scalar Core ML fixture
- mock sessions now intercept missing routes and invalidate before handler removal
- built the pinned whisper.cpp v1.7.5 xcframework for local verification
- rationale: establish reproducible unit tests before relying on coverage for the behavioral fixes
- version bump: 0.8.0 to 0.8.1 (PATCH - test infrastructure fixes; breaking API work has not started)


### 2026-06-11 (v0.8.0 — appleSpeech backend)

- **Apple Speech backend implemented.** `AppleSpeechBackend` actor conforms to `Transcriber`; models are BCP-47 locales (e.g. `en-US`); default from `Locale.current` with `en-US` fallback. No Hugging Face downloads — `AppleSpeechAssetInstaller` uses `AssetInventory.reserve` + `assetInstallationRequest`.
- **Runtime availability.** Package minimum stays macOS 14; `AppleSpeechSupport.isRuntimeAvailable()` gates the backend at runtime (macOS 26+). CLI `backend --list` annotates `(requires macOS 26+)` when unavailable.
- **LiveAPI shim pattern.** Speech framework isolation in `AppleSpeechBackend+LiveAPI.swift` (coverage-excluded); `AppleSpeechTranscriberBridge.make(model:)` holds `#available` transcriber construction so `BackendDispatch.swift` stays fully coverable.
- **Tests.** Six new suites (`AppleSpeechSupportTests`, `AppleSpeechBackendTests`, etc.); stub hooks for locale lists, transcription spans, and API availability without real Speech assets.

### 2026-05-19 (v0.7.10 — 100% region coverage gate)

- **Region coverage gate.** `_scripts/coverage.sh` now fails when SuperscribeKit **region** coverage drops below 100% (in addition to line coverage). Fifteen branch/region gaps closed with targeted tests and small dead-code removals (`AudioPreparer` progress fraction ternary).
- **`ModelInstaller.exerciseInstallLockEarlyReturnForTesting()`.** Covers the install-lock fast path when `LockSignal.wait()` runs after `fire()`.

### 2026-05-19 (v0.7.9 — DRY + 100% SuperscribeKit coverage policy)

- **DRY principle documented.** Primary instructions, a dedicated **DRY (Don't Repeat Yourself)** section under Best Practices, and Swift Coding Standards now require single authoritative implementations — search before writing, extract on the second duplication, and apply DRY to tests as well.
- **Mandatory 100% line coverage.** Primary instructions, Best Practices, and **Test Coverage (mandatory)** require `_scripts/coverage.sh --run-tests` to pass at 100% after every `SuperscribeKit` change. The gate must not be lowered; fix gaps with tests or documented exclusions only.

### 2026-05-19 (v0.7.9 — whisper tests without disk models)

- **No on-disk whisper.cpp models in tests.** Removed `transcribeMediumIntegrationWhenInstalled` and `transcribeSpeechExtractsWordsWhenMediumInstalled` (required `medium.bin` in the real cache). `WhisperBackend` gains `testUseStubLoad`, `testWhisperAPISegments`, and injected context/state pointers (`stub-*` model ids only) so failure paths and word extraction run without GGML downloads or inference.
- **`WhisperContext.testStub()`.** Placeholder context that skips `whisper_free` in deinit; enabled via `testUseStubLoad` and a `stub-*` model id so disk-load tests cannot accidentally pick up leaked hook state.
- **`WhisperBackend+LiveAPI.swift`.** whisper.cpp C API calls and stub/live branching live here; excluded from `_scripts/coverage.sh` via `-ignore-filename-regex` because live paths require a real GGML model. Unit tests exercise stub hooks in `WhisperBackend.swift` only.

### 2026-05-19 (v0.7.8 — Parakeet disk-load test stubs)

- **No HF downloads in Parakeet disk-load tests.** Removed tests that called real `AsrModels.load(from:)` on stub install dirs. Disk-load coverage uses `parakeetMaterializeFromDiskStub`, `parakeetAsrModelsLoad`, and `parakeetAsrManagerLoadModels` instead.
- **`TestHelpers.makeStubAsrModels()`.** Builds `AsrModels` from a macOS system Core ML bundle (`MapsSuggestionsTransportModePrediction.mlmodelc`); `AsrManager.loadModels` only stores references, so no inference or Hugging Face fetch is needed.
- **`parakeetAsrManagerLoadModels` moved.** Hook now applies inside `loadParakeetModelsIntoManager` (not early-return in `materializeFromDiskUsingFluidAudio`), so the load-assemble path stays covered without skipping `loadAsrModels`.

### 2026-05-19 (v0.7.7 — parallel-safe test harness)

- **Swift Testing parallelizes by default.** Shared hooks, path overrides, and mock URL handlers race when suites run concurrently. Use **`_scripts/test.sh`** or **`swift test --no-parallel -Xswiftc -strict-concurrency=complete`**. Plain `swift test` may flake.
- **`ResetSharedStateTrait`.** Every `@Suite` resets shared overrides before/after each test; all suites also use `.serialized`.
- **`MockURLSessionHelpers`.** Per-session handler map; `withMockHandler` passes `URLSession` into the body closure. Fast-path install tests use `URLSession.shared` when no mock is needed.
- **TaskLocal path/config overrides.** `SuperscribePaths.task*Directory` and `UserConfig.taskOverrideConfigFileURL` for per-task isolation in tests.

### 2026-05-19 (v0.7.6 — 100% SuperscribeKit line coverage gate)

- **Coverage gate passes.** `_scripts/coverage.sh --run-tests` reports **100.00%** SuperscribeKit line coverage; **307 tests** in 57 suites under `-strict-concurrency=complete` and `--no-parallel`.
- **Tier 4 gap tests.** `FinalLineCoverageGapTests` + `WhisperEncoderInstallerNetworkTests` cover nil-coalescing branches (manifest load failures, HF download totals, encoder zip size nil, Parakeet registry edge cases, `SuperscribeFS` listing failures).
- **Test hooks.** `SuperscribeKitTestHooks` adds `forceContentsOfDirectoryFailure`, `forceUnzipInvalidStderr`, `forceEncoderBundleEnumeratorNil`. `WhisperEncoderInstaller.decodeUnzipStderr(raw:)` extracted for branch coverage; `WhisperBackend` uses named `suppressLibraryLog` C callback + `invokeLogSuppressorsForTesting()`.
- **ModelDownloader.** `knownTotal` reduce uses force-unwrap after `allSatisfy` (drops unreachable `?? 0` in closure).

### 2026-05-19 (v0.7.5 — SuperscribeKit coverage tests)

- **`ModelInstaller.install(session:)`.** Optional `URLSession` argument (default `.shared`) threaded through downloads and `WhisperEncoderInstaller` so tests use `URLSession.mocked()` without global protocol registration.
- **`TestHelpers.withTempDirectory` async overload.** Supports `async throws` bodies used by downloader/installer network tests.
- **`ParakeetBackend.ensureLoaded`.** Fixed missing `return` before `loader.get { … }` (compile regression).
- **New test files (Swift Testing, `@testable`, explicit bool checks):** `MockURLSession.swift`, `UserConfigTests`, `DownloadProgressTrackerTests`, `ParakeetBackendTests`, `WhisperBackendTests`, `HuggingFaceHubNetworkTests`, `ModelDownloaderNetworkTests`, `ModelInstallerInstallTests`, `WhisperEncoderInstallerNetworkTests`, `IntermediateTranscriptTests`. Whisper integration test guards on `medium.bin`; Parakeet missing-model test guards when `tdt-ja` is installed.

### 2026-05-19 (v0.7.4 — Tier 3 DRY refactor + tests)

- **TestHelpers.swift.** Shared `makeTempDir`, `withTempDirectory`, `makeTempSineWAV`, `runMockPipeline`, and `MockTranscriber`; migrated Pipeline, ConvertedAudioCache, ModelInstaller, and CatalogStore tests.
- **TrackInputScanning.** Extracted `audioExtensions` + directory scan/sort/map from `TranscribeCommand.runCreateInput`; `TrackInputTests` cover filter, sort, speaker keys.
- **Backend resolution unified.** `BackendManager.resolveBackend(cliBackend:config:)` replaces `ModelCommand.resolvedBackend`; optional `config` param on `resolveBackendAndModel` for tests. `BackendManagerTests` cover CLI > config > built-in priority.
- **formatAge moved.** From private `CacheCommand` helper to `Utilities.swift` alongside `formatDate`; `FormatAgeTests` added.
- **Test cleanup.** Removed duplicate `WhisperRegistryTests.installPathUsesCacheDirectory`; fixed all `try! #require` to `throws` + `try #require`. 133 tests pass.

### 2026-05-19 (v0.7.3 — Tier 2 DRY refactor + tests)

- **`SuperscribeFS`.** `URL+SuperscribeFS.swift`: staging URLs, directory/file checks, `atomicReplace`, Core ML bundle detection.
- **`SuperscribePaths`.** Named accessors for all five intentional cache/config roots (not unified).
- **`ConcurrencyHelpers.withBoundedThrowingTaskGroup`.** Shared bounded concurrency for `ModelDownloader`, `Pipeline`, and Parakeet repo fetches.
- **`DownloadProgressTracker` + `DownloadProgressReporting`.** Extracted from `ModelDownloader`; encoder install uses shared progress tick helper.
- **`ProgressReporting.throttleInterval`.** Single ~10 Hz constant for download + conversion reporters.
- **`PipelineConfig.backend`.** Metadata now records the actual backend (was hardcoded `.parakeet`).
- **Empty-samples guard** moved from backends into `Pipeline.transcribeSegments`.
- **Default `Transcriber.isAvailable`** on Apple Silicon via protocol extension; backends drop duplicate `#if arch(arm64)`.
- **CLI utilities.** `assertMutuallyExclusive`, `confirm`, `printErr` in `Utilities.swift`; used by `ModelCommand` and `CacheCommand`.
- **Tests.** 30 new tests across `FilesystemHelpersTests`, `SuperscribePathsTests`, `CLIUtilitiesTests`, `HTTPValidationTests`, `ConcurrencyHelpersTests`, `SortingTests`, `WhisperEncoderInstallerTests`, `TranscriberAvailabilityTests`; extended `PipelineTests` and `ParakeetRegistryTests` (117 total).

### 2026-05-19 (v0.7.2 — Tier 1 DRY refactor + tests)

- **`PipelineRunner`.** Shared transcribe bootstrap for `transcribe` and `run` with injectable `Dependencies` for tests.
- **`TokenAccumulator`.** Unified sub-word → word merging for Parakeet and Whisper backends (`Backends/TokenMerging.swift`).
- **`Backend` dispatch.** `BackendDispatch.swift` centralizes `installPath`, `remoteModels`, `installedModels`, `makeTranscriber`, and `registryDefaultModelId`; `BackendManager`/`ModelManager`/`ModelInstaller.installPath` delegate to it.
- **`LoadOnce` actor.** Replaces per-backend `loadingTask` coalescing; clears in-flight task on failure for retry. `ModelInstallSupport.requireInstalled` shared preflight.
- **`ModelDownloader.streamBytes`.** Single async byte-stream writer for `downloadOne` and `downloadRepoFile`.
- **Shared Kit helpers.** `ByteFormatting`, `JSONCoding` (catalog/config/transcript encoders), `HTTPValidation.isSuccess`.
- **CLI helpers.** `saveIntermediateTranscript`, `printTranscribeSummary`, `defaultIntermediateOutputPath`, `clearProgressLine` in `Utilities.swift`.
- **Tests.** 33 new tests across `TokenMergingTests`, `PipelineRunnerTests`, `BackendDispatchTests`, `ModelDownloaderTests`, `JSONCodingTests`, `LoadOnceTests`, `CLIHelpersTests`, `ByteFormattingTests` (87 total).

### 2026-05-19 (v0.7.1 — coverage infrastructure, Tier 0 DRY refactor)

- **`_scripts/coverage.sh`.** Reports SuperscribeKit line coverage via `llvm-cov`; exits non-zero when below `COVERAGE_MIN` (default 100). Run `swift test --enable-code-coverage` first, or pass `--run-tests`. Baseline recorded in `_scripts/coverage-baseline.txt` (43.32% line coverage as of 2026-05-19).
- **Test target links CLI.** `superscribeTests` now depends on `superscribe` executable so future CLI helper tests can `@testable import superscribe`.

### 2026-05-19 (v0.7.0 — whisper Core ML encoder / ANE)

- **Unified whisper xcframework (Metal + Core ML).** `_scripts/bootstrap.sh` enables `WHISPER_COREML=1` and `WHISPER_COREML_ALLOW_FALLBACK=1` in the same CMake configure as `GGML_METAL`; merges `libwhisper.coreml.a` into the single static archive. `Package.swift` links `CoreML` and `Foundation`. Must rebuild `whisper-build/` after pull — never link a second Core-ML-only library.
- **Encoder bundle install.** `WhisperEncoderInstaller` auto-downloads `ggml-<base>-encoder.mlmodelc.zip` from Hugging Face alongside the `.bin`; installed as `{cache}/<base>-encoder.mlmodelc/`. Quantized model ids strip `-q5_0` etc. for encoder base name (matches whisper.cpp path logic).
- **Metal preserved.** Decoder and encoder fallback remain on Metal/GGML when the Core ML bundle is absent.

### 2026-05-19 (v0.6.2 — whisper perf + download progress)

- **Whisper decode speed.** `WhisperBackend` sets `ctxParams.flash_attn = true` (Metal fused attention) and `params.temperature_inc = 0.0` (skip temperature fallback re-runs on low-confidence segments).
- **Model download progress.** `ModelDownloader` reports the HF `rfilename` in progress ticks; throughput uses a 1 s sliding window with overall-average fallback so the rate column populates from the first byte. `ModelManager.makeDownloadProgressHandler` renders fixed-width columns with `ESC[2K` line clear; `String.rightPad` added in `Utilities.swift`.
- **Agent skills.** Duplicate `swift-testing-pro` under `.github/skills/` removed; `init-session` prompt moved to `.cursor/commands/init-session.md`. Skill frontmatter added for `git-workflow` and `semantic-versioning`.

### 2026-05-18 (v0.6.1 — CLI refactor + style sweep)

- **Flat CLI source layout.** Split `Sources/superscribe/Commands/Subcommands.swift` (1037 lines) into one file per command directly under `Sources/superscribe/`: `Superscribe.swift`, `Options.swift`, `TranscribeCommand.swift`, `MergeCommand.swift`, `RunCommand.swift`, `ModelCommand.swift`, `BackendCommand.swift`, `CacheCommand.swift`. The `Commands/` subdirectory is removed.
- **Backend/Model managers.** Extracted backend resolution and transcriber construction into `BackendManager` (with `resolveBackendAndModel`, `builtInDefaultModel`, `makeTranscriber`); extracted catalog fetch, install-state queries, and `ensureModelInstalled` into `ModelManager`. Both are `final class` with `private init()` and `static` methods. Shared CLI helpers (progress reporter, byte/date formatting, `String.leftPad`) live in `Utilities.swift`.
- **Explicit Bool comparisons.** Per project preference, all `if`/`guard`/`while`/`else if` boolean conditions across `Sources/` now compare explicitly: `!x` → `x == false`, bare `x` → `x == true`. Pattern bindings (`if let`, `if case`), `==`/`!=` comparisons, and ternaries are unchanged.
- **swift-format pass** over `Sources/` and `Package.swift` with the repo `.swift-format` config (Xcode 6.2.3 toolchain).

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

- **Whisper backend: migrated to whisper.cpp static xcframework (v0.5.0).** Replaced the `argmax-oss-swift` Swift package dependency with a static arm64 xcframework built from whisper.cpp v1.7.5 source. The xcframework is built once by `_scripts/bootstrap.sh` (requires cmake + ninja), output to `whisper-build/whisper.xcframework` (gitignored), and consumed via SPM `.binaryTarget(path:)`. `SuperscribeKit` gains `linkerSettings` for `Metal`, `MetalKit`, `Accelerate`, and `c++`. This pins the whisper.cpp C API version the user runs against regardless of their system state — API breakage is only ever visible when we deliberately upgrade the xcframework. Drops 6 transitive Swift deps (swift-transformers, swift-jinja, yyjson, swift-crypto, swift-asn1, swift-collections).
- **Model catalog changed.** Whisper models are now single GGML `.bin` files from `ggerganov/whisper.cpp` on HuggingFace. `defaultModelId = "large-v3-turbo"` (hyphen, not underscore). Install path changed from `~/Documents/huggingface/.../openai_whisper-<id>/` (old convention) to `~/Library/Caches/superscribe/whisper/<id>.bin`. Old model folders are orphaned; user can delete manually.
- **ModelInstaller single-file support.** `isInstalled(at:backend:)` for `.whisper` now checks for a regular file (not a directory + `.mlmodelc`). Staging uses a sibling `.bin.staging-<uuid>` file path (not a staging directory). `ModelDownloader.downloadFile(model:into:onProgress:)` added for single-file downloads.
- **WhisperBridge.swift deleted.** Bridging helpers (`extractWords`, `WKWord`) are no longer needed; whisper.cpp token data is read directly via C API in `WhisperBackend.extractTimedWords`.
- **Build integration.** `_scripts/bootstrap.sh` handles: prerequisite check (cmake/ninja), download of v1.7.5 tarball, cmake configure (arm64, Metal embedded, no examples/tests), ninja build, libtool combine of all `libggml*.a` + `libwhisper.a`, xcodebuild xcframework creation, module.modulemap injection.

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

### 2025-10-05 (v0.1.0, initial setup)

- initial AGENTS.md setup
- established core coding standards and conventions
- defined repository structure and governance principles
