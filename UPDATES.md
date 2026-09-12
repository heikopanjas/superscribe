# Recent Updates & Decisions

This file is the append-only log of project decisions and notable changes, maintained by coding agents following the `recent-updates` skill. Everything below the marker line is user-owned history: slopctl never overwrites it during init or merge.

<!-- {changelog} -->

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


### 2025-10-05 (v0.1.0, initial setup)

- initial AGENTS.md setup
- established core coding standards and conventions
- defined repository structure and governance principles
